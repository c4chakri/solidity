//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract UTToken is ERC20, Ownable, Pausable, ReentrancyGuard {
    mapping(address => bool) public blackListedAddress;
    mapping(address => uint256) public totalStakes;
    mapping(address => uint256) public stakeLockPeriods; // Mapping to track lock periods
    mapping(address => uint256) public stakeTimestamps; // Mapping to track stake timestamps
    uint16 public txnTaxRateBasisPoints;
    address public txnTaxWallet;
    uint8 private _decimals;
    IUniswapV2Router02 public uniswapRouter;

    struct smartContractActions {
        bool canMint;
        bool canBurn;
        bool canPause;
        bool canBlacklist;
        bool canChangeOwner;
        bool canTxTax;
        bool canBuyBack;
        bool canStake;
    }

    smartContractActions public actions;
    struct Stake {
        uint256 amount;
        uint256 stakeStartTimestamp;
        uint256 lockEndTimestamp; // The timestamp when the lock period ends
        bool unstaked;
    }

    mapping(address => Stake[]) public userStakes;

    event LogApproval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event LogTotalSupply(uint256 totalSupply, uint256 decimals);

    modifier canMintModifier() {
        require(
            actions.canMint,
            "Minting Functionality is not enabled in this smart contract!"
        );
        _;
    }

    modifier canBurnModifier() {
        require(
            actions.canBurn,
            "Burning Functionality is not enabled in this smart contract!"
        );
        _;
    }

    modifier canPauseModifier() {
        require(
            actions.canPause,
            "Pause/Unpause Functionality is not enabled in this smart contract!"
        );
        _;
    }

    modifier canBlacklistModifier() {
        require(
            actions.canBlacklist,
            "Blacklist Address Functionality is not enabled in this smart contract!"
        );
        _;
    }

    modifier canChangeOwnerModifier() {
        require(
            actions.canChangeOwner,
            "Change Owner Functionality is not enabled in this smart contract!"
        );
        _;
    }

    modifier canBuyBackModifier() {
        require(
            actions.canBuyBack,
            "Buyback Token Functionality is not enabled in this smart contract!"
        );
        _;
    }

    modifier canStakeModifier() {
        require(
            actions.canStake,
            "Staking reward Functionality is not enabled in this smart contract!"
        );
        _;
    }

    modifier canTxTaxModifier() {
        require(
            actions.canTxTax,
            "Txn Tax Functionality is not enabled in this smart contract!"
        );
        _;
    }
    modifier isBlackListed() {
        require(!blackListedAddress[msg.sender], "User is blacklisted!");
        _;
    }

    constructor(
        uint256 preMintValue,
        string memory _tokenTicker,
        string memory _tokenName,
        address _initialAddress,
        smartContractActions memory _actions,
        uint16 _txnTaxRateBasisPoints,
        address _txnTaxWallet,
        uint8 decimals_
    ) ERC20(_tokenName, _tokenTicker) Ownable(_initialAddress) {
        _decimals = decimals_;
        initializeToken(preMintValue);
        initializeTaxSettings(_txnTaxRateBasisPoints, _txnTaxWallet);
        initializeFeatures(_actions);
    }

    function initializeToken(uint256 preMintValue) internal {
        uint256 convertedValue = convertDecimals(preMintValue);
        _mint(address(this), convertedValue);
        approve(owner(), convertedValue);
        emit LogTotalSupply(totalSupply(), decimals());
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function initializeTaxSettings(uint16 _txnTaxRate, address _txnTaxWallet)
        internal
    {
        require(_txnTaxWallet != address(0), "TxnTax Wallet can't be empty");
        txnTaxWallet = _txnTaxWallet;
        txnTaxRateBasisPoints = _txnTaxRate;
    }

    function initializeFeatures(smartContractActions memory _actions) private {
        actions.canStake = _actions.canStake;
        actions.canBurn = _actions.canBurn;
        actions.canMint = _actions.canMint;
        actions.canPause = _actions.canPause;
        actions.canBlacklist = _actions.canBlacklist;
        actions.canChangeOwner = _actions.canChangeOwner;
        actions.canTxTax = _actions.canTxTax;
        actions.canBuyBack = _actions.canBuyBack;
    }

    function pauseTokenTransfers() public canPauseModifier onlyOwner {
        require(!paused(), "Contract is already paused.");
        _pause();
    }

    function unPauseTokenTransfers() public canPauseModifier onlyOwner {
        require(paused(), "Contract is not paused.");
        _unpause();
    }

    function transferOwnership(address newOwner)
        public
        override
        canChangeOwnerModifier
        onlyOwner
    {
        _transferOwnership(newOwner);
    }

    function convertDecimals(uint256 _amount) private view returns (uint256) {
        return _amount * 10**decimals();
    }

    function transferTokensToUser(
        address user,
        uint256 amount,
        uint8 _duration
    ) public onlyOwner whenNotPaused {
        require(
            balanceOf(address(this)) >= amount,
            "Contract does not have enough tokens"
        );
        require(!blackListedAddress[user], "User is blacklisted");
        require(amount > 0, "Transfer amount must be greater than zero");

        // Monthly burn calculation = amount divided by the duration (in months).
        // Assume _duration is in days and calculate how many months (_duration).
        uint256 transferAmount = amount;
        uint256 monthlyBurnLimit = transferAmount / (_duration);

        // Calculate tax if transactions tax is enabled
        if (actions.canTxTax) {
            require(
                txnTaxRateBasisPoints > 0,
                "set txnTaxRateBasisPoints more zero"
            );
            // Calculate the tax in basis points (1% = 1000 basis points)
            uint256 taxAmount = (transferAmount * txnTaxRateBasisPoints) /
                (100 * 1000);
            // Dividing by 100,000 because 1% = 1000 basis points
            // 100*1000 => percent * basisPoints
            transferAmount = transferAmount - taxAmount;
            // Transfer tax to tax wallet
            _transfer(address(this), txnTaxWallet, taxAmount);
        }
        _transfer(address(this), user, transferAmount);
        _approve(user, owner(), monthlyBurnLimit);
    }

    function blackListUser(address _user)
        public
        canBlacklistModifier
        onlyOwner
        whenNotPaused
    {
        require(
            !blackListedAddress[_user],
            "User Address is already blacklisted"
        );
        blackListedAddress[_user] = true;
    }

    function whiteListUser(address _user)
        public
        canBlacklistModifier
        onlyOwner
        whenNotPaused
    {
        require(blackListedAddress[_user], "User Address is not blacklisted");
        blackListedAddress[_user] = false;
    }

    function setTxnTaxRateBasisPoints(uint16 _rateValue)
        public
        canTxTaxModifier
        onlyOwner
        whenNotPaused
    {
        require(_rateValue > 0, "Rate must be grater than 0");
        txnTaxRateBasisPoints = _rateValue;
    }

    function setTxnTaxWallet(address _txnTaxWallet)
        public
        canTxTaxModifier
        onlyOwner
        whenNotPaused
    {
        require(_txnTaxWallet != address(0), "Txn tax wallet can't be empty");
        txnTaxWallet = _txnTaxWallet;
    }

    function buyBackTokens(uint256 amountOutMin)
        external
        payable
        canBuyBackModifier
        whenNotPaused
    {
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH(); //Weth contract address
        path[1] = address(this); // erc20 address of this contract

        uniswapRouter.swapExactETHForTokens{value: msg.value}(
            amountOutMin, //amount of tokens wants to buy back from market
            path, //
            address(this), // Tokens bought will be sent to the contract
            block.timestamp + 300 // Deadline
        );
    }

    function mintSupply(uint256 _amount)
        public
        canMintModifier
        onlyOwner
        whenNotPaused
    {
        require(_amount > 0, "Mint more than Zero");
        _mint(address(this), convertDecimals(_amount));
    }

    function burnSupply(uint256 _amount)
        public
        canBurnModifier
        onlyOwner
        whenNotPaused
    {
        require(_amount > 0, "Burn more than Zero");
        _burn(address(this), convertDecimals(_amount));
    }

    // function stakeToken(uint256 _amount, uint256 lockPeriod)
    //     public
    //     canStakeModifier
    //     nonReentrant
    //     whenNotPaused
    //     isBlackListed
    // {
    //     require(
    //         balanceOf(msg.sender) >= _amount,
    //         "Insufficient token balance to stake"
    //     );
    //     require(
    //         lockPeriod >= 1 && lockPeriod <= 12,
    //         "Lock period must be between 1 and 12 months"
    //     );
    //     stakes[msg.sender] += _amount;
    //     stakeLockPeriods[msg.sender] = lockPeriod * 30 days; // Lock period
    //     stakeTimestamps[msg.sender] = block.timestamp; // Record the staking time
    //     _transfer(msg.sender, address(this), _amount);
    // }

    function unStakeTotalAmount()
        external
        canStakeModifier
        nonReentrant
        whenNotPaused
        isBlackListed
    {
        require(totalStakes[msg.sender] > 0, "User doesn't have any staked token!");
        require(
            block.timestamp >=
                stakeTimestamps[msg.sender] + stakeLockPeriods[msg.sender],
            "Tokens are still locked"
        );
        uint256 amountToUnstake = totalStakes[msg.sender];
        totalStakes[msg.sender] = 0;
        _transfer(address(this), msg.sender, amountToUnstake);
    }

    event Staked(
        address indexed user,
        uint256 amount,
        uint256 lockEndTimestamp
    );
    event Unstaked(address indexed user, uint256 amount);

    function stake(uint256 _amount, uint256 _lockDuration)
        external
        canStakeModifier
        nonReentrant
        whenNotPaused
        isBlackListed
    {
        require(_amount > 0, "Amount must be greater than zero");
        require(_lockDuration > 0, "Lock duration must be greater than zero");

        Stake memory newStake = Stake({
            amount: _amount,
            stakeStartTimestamp: block.timestamp,
            lockEndTimestamp: block.timestamp + (_lockDuration * 30 days),
            unstaked: false
        });
        totalStakes[msg.sender] += _amount;
        userStakes[msg.sender].push(newStake);
        _transfer(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount, newStake.lockEndTimestamp);
    }

  function unstakeToken(uint256 _amount) external canStakeModifier
        nonReentrant
        whenNotPaused
        isBlackListed{
        require(_amount > 0, "Amount must be greater than zero");
        uint256 remainingAmountToUnstake = _amount;
        uint256 totalUnstakedAmount = 0;

        // Loop through the user's stakes in reverse order
        for (uint256 i = userStakes[msg.sender].length; i > 0; i--) {
            Stake storage userStake = userStakes[msg.sender][i - 1];

            // If the stake is not yet fully unstaked
            if (!userStake.unstaked) {
                if (userStake.amount <= remainingAmountToUnstake) {
                    // Fully unstake this stake
                    remainingAmountToUnstake -= userStake.amount;
                    totalUnstakedAmount += userStake.amount;
                    userStake.amount = 0;
                    userStake.unstaked = true; // Mark as fully unstaked
                } else {
                    // Partially unstake from this stake
                    totalUnstakedAmount += remainingAmountToUnstake;
                    userStake.amount -= remainingAmountToUnstake;
                    remainingAmountToUnstake = 0;
                }

                // If we've unstaked the full requested amount, exit the loop
                if (remainingAmountToUnstake == 0) {
                    break;
                }
            }
        }

        require(totalUnstakedAmount == _amount, "Not enough staked balance to unstake the requested amount");

        // Transfer the unstaked tokens back to the user
        // Assuming the contract holds the staked tokens
        totalStakes[msg.sender]-= totalUnstakedAmount;
        _transfer(address(this), msg.sender, totalUnstakedAmount);

        emit Unstaked(msg.sender, totalUnstakedAmount);
    }
    // function unstakeToken(uint256 _amount) external {
    //     require(_amount > 0, "Amount must be greater than zero");
    //     uint256 totalUnstakedAmount = 0;

    //     for (uint256 i = 0; i < userStakes[msg.sender].length; i++) {
    //         Stake storage userStake = userStakes[msg.sender][i];
    //         if (_amount >= totalUnstakedAmount && !userStake.unstaked) {
    //             totalUnstakedAmount += userStake.amount;
    //             userStake.amount-= totalUnstakedAmount - userStake.amount;
    //             userStake.unstaked = true;

    //             if(totalUnstakedAmount>= _amount){
    //                 break ;
    //             }
    //         }
    //     }
    //     _transfer(address(this), msg.sender, totalUnstakedAmount);
    //     emit Unstaked(msg.sender, totalUnstakedAmount);
    // }

    // function unstakeToken(uint256 _amount)
    //     public
    //     canStakeModifier
    //     nonReentrant
    //     isBlackListed
    // {
    //     require(
    //         stakes[msg.sender] >= _amount,
    //         "User doesn't have enough staked token!"
    //     );
    //     require(
    //         block.timestamp >=
    //             stakeTimestamps[msg.sender] + stakeLockPeriods[msg.sender],
    //         "Tokens are still locked"
    //     );
    //     stakes[msg.sender] -= _amount;
    //     _transfer(address(this), msg.sender, _amount);
    // }

    function burnFrom(address _user, uint256 _amount) public onlyOwner {
        uint256 currentAllowance = allowance(_user, owner());
        require(currentAllowance >= _amount, "Burn amount exceeds allowance");
        uint256 userBalance = balanceOf(_user);
        if (userBalance == 0) {
            _approve(_user, owner(), 0);
        }
        _burn(_user, _amount);
    }
}
