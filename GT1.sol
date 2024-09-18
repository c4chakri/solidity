// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract GovernanceToken is
    ERC20,
    Pausable,
    ReentrancyGuard,
    Ownable,
    ERC20Permit,
    ERC20Votes,
    AccessControl
{

    error GovernanceERC20unAuthorizedRole();
    error GovernanceERC20IdNotFound();
    error GovernanceERC20InsufficientBalance();
    error GovernanceERC20MintNotEnabled();
    error GovernanceERC20BurnNotEnabled();
    error GovernanceERC20PauseNotEnabled();
    error GovernanceERC20StakeNotEnabled();
    error GovernanceERC20TransferNotEnabled();
    error GovernanceERC20ChangeOwnerNotEnabled();

    uint8 private _decimals;
    bytes32 private constant MINTER_ROLE = keccak256("TOKEN_MINTER");
    bytes32 private constant BURNER_ROLE = keccak256("TOKEN_BURNER");
    bytes32 private constant TRANSFER_ROLE = keccak256("TOKEN_TRANSFER");
    bytes32 private constant GOVERNER_COUNCIL = keccak256("TOKEN_GOVERNER");

    struct smartContractActions {
        bool canMint;
        bool canBurn;
        bool canPause;
        bool canStake;
        bool canTransfer;
        bool canChangeOwner;
    }
    smartContractActions public actions;

    mapping(address => address) public daoAddress;

    constructor(
        string memory name,
        string memory symbol,
        address councilAddress,
        uint8 decimals_,
        smartContractActions memory _actions
    ) ERC20(name, symbol) Ownable(councilAddress) ERC20Permit(name) {
        daoAddress[address(this)] = address(0);
        initializeFeatures(_actions);
        _decimals = decimals_;
        _grantRole(MINTER_ROLE, councilAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, councilAddress);
        _grantRole(GOVERNER_COUNCIL,councilAddress);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function initializeFeatures(smartContractActions memory _actions) internal {
        actions.canStake = _actions.canStake;
        actions.canBurn = _actions.canBurn;
        actions.canMint = _actions.canMint;
        actions.canPause = _actions.canPause;
        actions.canTransfer = _actions.canTransfer;
        actions.canChangeOwner = _actions.canChangeOwner;
    }

    modifier auth(bytes32 action) {
        require(
            hasRole(MINTER_ROLE, msg.sender) ||
                hasRole(BURNER_ROLE, msg.sender) ||
                hasRole(TRANSFER_ROLE, msg.sender),
            GovernanceERC20unAuthorizedRole()
        );
        _;
    }

    function mintSupply(address to, uint256 _amount)
        public
        nonReentrant
        whenNotPaused
        auth(MINTER_ROLE)
    {
        _mint(to, _amount);
    }

    function burnSupply(address from, uint256 _amount)
        public
        canBurnModifier
        nonReentrant
        whenNotPaused
        auth(BURNER_ROLE)
    {
        _burn(from, _amount);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        canTransfer
        nonReentrant
        whenNotPaused
        auth(TRANSFER_ROLE)
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function setDAOAddress(address _daoAddress) external  {
        require(_daoAddress != address(0), "Invalid DAO address");
        daoAddress[msg.sender] = _daoAddress;
        _grantRole(MINTER_ROLE, _daoAddress);
        _grantRole(BURNER_ROLE, _daoAddress);
        _grantRole(TRANSFER_ROLE, _daoAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, _daoAddress);
        // revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // revokeRole(MINTER_ROLE, msg.sender);
    }

    function pause() public canPauseModifier whenNotPaused {
        require(!paused(), "Contract is already paused.");
        _pause();
    }

    function unpause() public canPauseModifier whenPaused {
        require(paused(), "Contract is not paused.");
        _unpause();
    }

    function transferOwnership(address _newOwner)
        public
        override
        onlyOwner
        canChangeOwner
    {
        require(_newOwner != address(0), "New owner is the zero address");
        require(owner() != _newOwner, "Provided User is already an Owner");
        super.transferOwnership(_newOwner);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) whenNotPaused {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }

    function votesDemo(address account) public view returns (uint256) {
        ERC20Votes erc20 = ERC20Votes(address(this));
        return erc20.getVotes(account);
    }

    function _getVotingUnits(address account)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return balanceOf(account);
    }

    modifier canMintModifier() {
        require(actions.canMint, GovernanceERC20MintNotEnabled());
        _;
    }

    modifier canBurnModifier() {
        require(actions.canBurn, GovernanceERC20BurnNotEnabled());
        _;
    }

    modifier canPauseModifier() {
        require(actions.canPause, GovernanceERC20PauseNotEnabled());
        _;
    }

    modifier canStakeModifier() {
        require(actions.canStake, GovernanceERC20StakeNotEnabled());
        _;
    }
    modifier canTransfer() {
        require(actions.canTransfer, GovernanceERC20TransferNotEnabled());
        _;
    }

    modifier canChangeOwner() {
        require(actions.canChangeOwner, GovernanceERC20ChangeOwnerNotEnabled());
        _;
    }
}

// [true,true,true,true,true,true]
