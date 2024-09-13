
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
    mapping(address => uint256) public stakeLockPeriods;
    mapping(address => uint256) public stakeTimestamps;
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
        uint256 lockEndTimestamp;
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
    event Staked(
        address indexed user,
        uint256 amount,
        uint256 lockEndTimestamp
    );
    event Unstaked(address indexed user, uint256 amount);

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

    /**
     * @dev Initializes the token with the specified pre-minted value.
     *
     * @param preMintValue The amount of tokens to pre-mint.
     */
    function initializeToken(uint256 preMintValue) internal {
        uint256 convertedValue = convertDecimals(preMintValue);
        _mint(address(this), convertedValue);
        approve(owner(), convertedValue);
        emit LogTotalSupply(totalSupply(), decimals());
    }

    /**
     * @dev Returns the number of decimals for this token.
     *
     * @return uint8 The number of decimals.
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Initializes the tax settings for the token.
     *
     * @param _txnTaxRate The tax rate as a percentage.
     * @param _txnTaxWallet The wallet address to which taxes will be sent.
     */
    function initializeTaxSettings(uint16 _txnTaxRate, address _txnTaxWallet)
        internal
    {
        require(_txnTaxWallet != address(0), "TxnTax Wallet can't be empty");
        txnTaxWallet = _txnTaxWallet;
        txnTaxRateBasisPoints = _txnTaxRate;
    }

    /**
     * @dev Initializes the features for the token.
     *
     * @param _actions The features to initialize.
     */
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

    /**
     * @dev Converts a given amount to the correct number of decimals for the token.
     *
     * @param _amount The amount to convert.
     *
     * @return uint256 The converted amount.
     */
    function convertDecimals(uint256 _amount) private view returns (uint256) {
        return _amount * 10**decimals();
    }

    /**
     * @notice Allows the owner to transfer a specified amount of tokens to a user.
     * @dev This function transfers the tokens to the user and updates the user's balance.
     * @param user The address of the user to transfer the tokens to.
     * @param amount The amount of tokens to transfer.
     * @param _duration The duration for which the transfer is valid.
     */
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

        uint256 transferAmount = amount;
        uint256 monthlyBurnLimit = transferAmount / _duration;

        if (actions.canTxTax) {
            require(
                txnTaxRateBasisPoints > 0,
                "Tax rate must be greater than zero"
            );
            uint256 taxAmount = (transferAmount * txnTaxRateBasisPoints) /
                (100 * 1000);
            transferAmount -= taxAmount;
            _transfer(address(this), txnTaxWallet, taxAmount);
        }
        _transfer(address(this), user, transferAmount);
        _approve(user, owner(), monthlyBurnLimit);
    }

    /**
     * @notice Blacklists a specified user address.
     * @dev This function adds the user address to the blacklisted addresses array and prevents any further interactions with the contract.
     * @param _user The address of the user to blacklist.
     */
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

    /**
     * @dev White lists a specified user address.
     *
     * @param _user The address of the user to white list.
     */
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

    /**
     * @dev Allows the owner to mint a specified amount of tokens.
     *
     * @param _amount The amount of tokens to mint.
     */
    function mintSupply(uint256 _amount)
        public
        canMintModifier
        onlyOwner
        whenNotPaused
    {
        require(_amount > 0, "Mint more than Zero");
        _mint(address(this), convertDecimals(_amount));
    }

    /**
     * @dev Burns a specified amount of tokens from the contract.
     *
     * @param _amount The amount of tokens to burn.
     */
    /**
     * @dev Burns a specified amount of tokens from the contract.
     *
     * @param _amount The amount of tokens to burn.
     */
    function burnSupply(uint256 _amount)
        public
        canBurnModifier
        onlyOwner
        whenNotPaused
    {
        require(_amount > 0, "Burn more than Zero");
        _burn(address(this), convertDecimals(_amount));
    }
    
    /**
     * @notice Allows a user to unstake their total amount of tokens.
     *
     * @dev This function unstakes the user's entire balance of tokens and transfers them to the user's wallet.
     */
    function unStakeTotalAmount()
        external
        canStakeModifier
        nonReentrant
        whenNotPaused
        isBlackListed
    {
        require(
            totalStakes[msg.sender] > 0,
            "User doesn't have any staked token!"
        );
        // require(
        //     block.timestamp >=
        //         stakeTimestamps[msg.sender] + stakeLockPeriods[msg.sender],
        //     "Tokens are still locked"
        // );
        uint256 amountToUnstake = totalStakes[msg.sender];
        totalStakes[msg.sender] = 0;
        _transfer(address(this), msg.sender, amountToUnstake);
    }

    /**
     * @notice Allows a user to stake a specified amount of tokens.
     * @dev This function adds a new stake to the user's stakes array and updates their total staked amount.
     * @param _amount The amount of tokens to stake.
     * @param _lockDuration The lock duration for the staked tokens in days.
     * @param _lockDuration The lock duration for the staked tokens in days.
     */
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

    /**
     * @notice Allows a user to unstake a specified amount of tokens.
     * @dev This function iterates over the user's stakes, unstaking the requested amount from the earliest stake first.
     * @param _amount The amount of tokens to unstake.
     */
    function unstakeToken(uint256 _amount)
        external
        canStakeModifier
        nonReentrant
        whenNotPaused
        isBlackListed
    {
        require(_amount > 0, "Amount must be greater than zero");
        uint256 remainingAmountToUnstake = _amount;
        uint256 totalUnstakedAmount = 0;

        for (uint256 i = userStakes[msg.sender].length; i > 0; i--) {
            Stake storage userStake = userStakes[msg.sender][i - 1];

            if (!userStake.unstaked) {
                if (userStake.amount <= remainingAmountToUnstake) {
                    remainingAmountToUnstake -= userStake.amount;
                    totalUnstakedAmount += userStake.amount;
                    userStake.amount = 0;
                    userStake.unstaked = true;
                } else {
                    totalUnstakedAmount += remainingAmountToUnstake;
                    userStake.amount -= remainingAmountToUnstake;
                    remainingAmountToUnstake = 0;
                }

                if (remainingAmountToUnstake == 0) {
                    break;
                }
            }
        }

        require(
            totalUnstakedAmount == _amount,
            "Not enough staked balance to unstake the requested amount"
        );

        totalStakes[msg.sender] -= totalUnstakedAmount;
        _transfer(address(this), msg.sender, totalUnstakedAmount);

        emit Unstaked(msg.sender, totalUnstakedAmount);
    }

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
