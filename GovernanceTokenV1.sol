// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
contract GovernanceToken is
    Initializable,
    UUPSUpgradeable,
    ERC20Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    ERC20VotesUpgradeable
{
    mapping(address => uint256) public userStakedBalance;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    // The initializer function to replace the constructor
    function initialize(
        string memory name,
        string memory symbol,
        address _initialAddress,
        uint8 decimals_,
        smartContractActions memory _actions
    ) public initializer {
        __ERC20_init(name, symbol);
        __Ownable_init(_initialAddress);
        __ERC20Permit_init(name);
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        daoAddress[address(this)] = address(0);
        initializeFeatures(_actions);
        _decimals = decimals_;
        _grantRole(MINTER_ROLE, _initialAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAddress);
    }
    function version() public pure returns (string memory) {
        return "0.0.1";
    }
 
    
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

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

    function setDAOAddress(address _daoAddress) external onlyOwner {
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
    ) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) whenNotPaused {
        super._update(from, to, value);
    }

    function nonces(address owner) public override(ERC20PermitUpgradeable,NoncesUpgradeable)  view returns (uint256) {
        return super.nonces(owner);
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
//0x5c80c26C8a807e1Af22AE1db89D157453F7F6aF8
