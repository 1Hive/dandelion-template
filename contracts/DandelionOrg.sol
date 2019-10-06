pragma solidity 0.4.24;

import "@aragon/templates-shared/contracts/BaseTemplate.sol";

import "@1hive/apps-redemptions/contracts/Redemptions.sol";
import "@1hive/apps-time-lock/contracts/TimeLock.sol";
import "@1hive/apps-token-request/contracts/TokenRequest.sol";
import "@1hive/apps-delay/contracts/Delay.sol";
import "@1hive/oracle-token-balance/contracts/TokenBalanceOracle.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";


contract DandelionOrg is BaseTemplate {
    string constant private ERROR_EMPTY_HOLDERS = "DANDELION_EMPTY_HOLDERS";
    string constant private ERROR_BAD_HOLDERS_STAKES_LEN = "DANDELION_BAD_HOLDERS_STAKES_LEN";
    string constant private ERROR_BAD_VOTE_SETTINGS = "DANDELION_BAD_VOTE_SETTINGS";
    string constant private ERROR_BAD_PAYROLL_SETTINGS = "DANDELION_BAD_PAYROLL_SETTINGS";
    string constant private ERROR_MISSING_CACHE = "DANDELION_MISSING_CACHE";
    string constant private ERROR_MISSING_TOKEN_CACHE = "DANDELION_MISSING_TOKEN_CACHE";
    string constant private ERROR_BAD_TOKENREQUEST_TOKEN_LIST = "DANDELION_BAD_TOKENREQUEST_TOKEN_LIST";
    string constant private ERROR_TIMELOCK_TOKEN_NOT_CONTRACT = "DANDELION_TIMELOCK_TOKEN_NOT_CONTRACT";
    string constant private ERROR_BAD_TIMELOCK_SETTINGS = "DANDELION_BAD_TIMELOCK_SETTINGS";
    string constant private ERROR_BAD_VOTING_SETTINGS = "DANDELION_BAD_VOTING_SETTINGS";

    bool constant private TOKEN_TRANSFERABLE = false;
    uint8 constant private TOKEN_DECIMALS = uint8(18);
    uint256 constant private TOKEN_MAX_PER_ACCOUNT = uint256(0);
    uint64 constant private DEFAULT_FINANCE_PERIOD = uint64(30 days);

    bytes32 constant private REDEMPTIONS_APP_ID = keccak256(abi.encodePacked(apmNamehash("open"), keccak256("redemptions")));
    bytes32 constant private TOKEN_REQUEST_APP_ID = keccak256(abi.encodePacked(apmNamehash("open"), keccak256("token-request")));
    bytes32 constant private TIME_LOCK_APP_ID = keccak256(abi.encodePacked(apmNamehash("open"), keccak256("time-lock")));
    bytes32 constant private DELAY_APP_ID = keccak256(abi.encodePacked(apmNamehash("open"), keccak256("delay")));
    bytes32 constant private TOKEN_BALANCE_ORACLE_APP_ID = keccak256(abi.encodePacked(apmNamehash("open"), keccak256("token-balance-oracle")));

    address constant ANY_ENTITY = address(-1);
    uint8 constant ORACLE_PARAM_ID = 203;
    enum Op { NONE, EQ, NEQ, GT, LT, GTE, LTE, RET, NOT, AND, OR, XOR, IF_ELSE }

    struct Cache {
        address dao;
        address token;
        address tokenManager;
        address agentOrVault;
        address finance;
        address dandelionVoting;
        address redemptions;
        address tokenRequest;
        address timeLock;
        address delay;
        address tokenBalanceOracle;
        bool agentAsVault;
    }

    mapping (address => Cache) internal cache;

    constructor(DAOFactory _daoFactory, ENS _ens, MiniMeTokenFactory _miniMeFactory, IFIFSResolvingRegistrar _aragonID)
        BaseTemplate(_daoFactory, _ens, _miniMeFactory, _aragonID)
        public
    {
        _ensureAragonIdIsValid(_aragonID);
        _ensureMiniMeFactoryIsValid(_miniMeFactory);
    }

    /**
    * @dev Create a new MiniMe token and deploy a Dandelion Org DAO. This function does not allow Payroll
    *      to be setup due to gas limits.
    * @param _tokenName String with the name for the token used by share holders in the organization
    * @param _tokenSymbol String with the symbol for the token used by share holders in the organization
    * @param _id String with the name for org, will assign `[id].aragonid.eth`
    * @param _holders Array of token holder addresses
    * @param _stakes Array of token stakes for holders (token has 18 decimals, multiply token amount `* 10^18`)
    * @param _financePeriod Initial duration for accounting periods, it can be set to zero in order to use the default of 30 days.
    * @param _useAgentAsVault Boolean to tell whether to use an Agent app as a more advanced form of Vault app
    */
    function newTokenAndBaseInstance(
        string _tokenName,
        string _tokenSymbol,
        string _id,
        address[] _holders,
        uint256[] _stakes,
        uint64 _financePeriod,
        bool _useAgentAsVault
    )
        external
    {
        newToken(_tokenName, _tokenSymbol);
        newBaseInstance(_id, _holders, _stakes, _financePeriod, _useAgentAsVault);
    }

    /**
    * @dev Install the Dandelion set of apps
    * @param _id String with the name for org, will assign `[id].aragonid.eth`
    * @param _redemptionsRedeemableTokens address[] with the list of redeemable tokens for redemptions app
    * @param _tokenRequestAcceptedDepositTokens address[] with the list of accepted deposit tokens for token request
    * @param _timeLockToken Address of the token for the lock app`
    * @param _timeLockSettings Array of [_lockDuration, _lockAmount, _spamPenaltyFactor] to set up the timeLock app of the organization
    * @param _votingSettings Array of [supportRequired, minAcceptanceQuorum, voteDuration] to set up the voting app of the organization
    * @param _executionDelay execution delay time to set up the delay app
    */
    function installDandelionApps(
        string _id,
        address[] _redemptionsRedeemableTokens,
        address[] _tokenRequestAcceptedDepositTokens,
        address _timeLockToken,
        uint256[3] _timeLockSettings,
        uint64[3] _votingSettings,
        uint64 _executionDelay
    )
        external
    {
        _ensureBaseAppsCache();
        Kernel dao = _popDaoCache();
        ACL acl = ACL(dao.acl());
        bool agentAsVault = _popAgentAsVaultCache();
        (,,Finance finance) = _popBaseAppsCache();

        _installDandelionApps(dao, _redemptionsRedeemableTokens, _tokenRequestAcceptedDepositTokens, _timeLockToken, _timeLockSettings, _votingSettings, _executionDelay);
        (Voting dandelionVoting,,,,,) = _popDandelionAppsCache();

        _setupBasePermissions(acl, agentAsVault);
        _setupDandelionPermissions(acl);

        _transferCreatePaymentManagerFromTemplate(acl, finance, dandelionVoting);
        _transferRootPermissionsFromTemplateAndFinalizeDAO(dao, dandelionVoting);
        _registerID(_id, address(dao));
        _clearCache();
    }

    /**
    * @dev Create a new MiniMe token and cache it for the user
    * @param _name String with the name for the token used by share holders in the organization
    * @param _symbol String with the symbol for the token used by share holders in the organization
    */
    function newToken(string memory _name, string memory _symbol) public returns (MiniMeToken) {
        MiniMeToken token = _createToken(_name, _symbol, TOKEN_DECIMALS);
        _cacheToken(token);
        return token;
    }

    /**
    * @dev Deploy a Dandelion Org DAO using a previously cached MiniMe token
    * @param _id String with the name for org, will assign `[id].aragonid.eth`
    * @param _holders Array of token holder addresses
    * @param _stakes Array of token stakes for holders (token has 18 decimals, multiply token amount `* 10^18`)
    * @param _financePeriod Initial duration for accounting periods, it can be set to zero in order to use the default of 30 days.
    * @param _useAgentAsVault Boolean to tell whether to use an Agent app as a more advanced form of Vault app
    */
    function newBaseInstance(
        string memory _id,
        address[] memory _holders,
        uint256[] memory _stakes,
        uint64 _financePeriod,
        bool _useAgentAsVault
    )
        public
    {
        _validateId(_id);
        _ensureBaseSettings(_holders, _stakes);

        (Kernel dao, ACL acl) = _createDAO();
        _setupBaseApps(dao, acl, _holders, _stakes, _financePeriod, _useAgentAsVault);

    }

    /**
    * @dev Deploy a Dandelion Org DAO using a previously cached MiniMe token
    * @param _id String with the name for org, will assign `[id].aragonid.eth`
    * @param _holders Array of token holder addresses
    * @param _stakes Array of token stakes for holders (token has 18 decimals, multiply token amount `* 10^18`)
    * @param _financePeriod Initial duration for accounting periods, it can be set to zero in order to use the default of 30 days.
    * @param _useAgentAsVault Boolean to tell whether to use an Agent app as a more advanced form of Vault app
    * @param _payrollSettings Array of [address denominationToken , IFeed priceFeed, uint64 rateExpiryTime, address employeeManager]
             for the payroll app. The `employeeManager` can be set to `0x0` in order to use the voting app as the employee manager.
    */
    function newBaseInstance(
        string memory _id,
        address[] memory _holders,
        uint256[] memory _stakes,
        uint64 _financePeriod,
        bool _useAgentAsVault,
        uint256[4] memory _payrollSettings
    )
        public
    {
        _validateId(_id);
        _ensureBaseSettings(_holders, _stakes, _payrollSettings);

        (Kernel dao, ACL acl) = _createDAO();
        _setupBaseApps(dao, acl, _holders, _stakes, _financePeriod, _useAgentAsVault);

    }


    function _setupBaseApps(
        Kernel _dao,
        ACL _acl,
        address[] memory _holders,
        uint256[] memory _stakes,
        uint64 _financePeriod,
        bool _useAgentAsVault
    )
        internal
    {
        MiniMeToken token = _popTokenCache();
        Vault agentOrVault = _useAgentAsVault ? _installDefaultAgentApp(_dao) : _installVaultApp(_dao);
        Finance finance = _installFinanceApp(_dao, agentOrVault, _financePeriod == 0 ? DEFAULT_FINANCE_PERIOD : _financePeriod);
        TokenManager tokenManager = _installTokenManagerApp(_dao, token, TOKEN_TRANSFERABLE, TOKEN_MAX_PER_ACCOUNT);

        _mintTokens(_acl, tokenManager, _holders, _stakes);
        _cacheBaseApps(_dao, tokenManager, agentOrVault, finance);

    }

    function _installDandelionApps(
        Kernel _dao,
        address[] memory _redemptionsRedeemableTokens,
        address[] memory _tokenRequestAcceptedDepositTokens,
        address _timeLockToken,
        uint256[3] memory _timeLockSettings,
        uint64[3] memory _votingSettings,
        uint64 _executionDelay
    )
        internal
    {
        _ensureDandelionSettings(_tokenRequestAcceptedDepositTokens, _timeLockToken, _timeLockSettings, _votingSettings);
        MiniMeToken token = _popTokenCache();
        Voting dandelionVoting = _installVotingApp(_dao, token, _votingSettings);
        Redemptions redemptions = _installRedemptionsApp(_dao, _redemptionsRedeemableTokens);
        TokenRequest tokenRequest = _installTokenRequestApp(_dao, _tokenRequestAcceptedDepositTokens);
        TimeLock timeLock = _installTimeLockApp(_dao, _timeLockToken, _timeLockSettings);
        Delay delay = _installDelayApp(_dao, _executionDelay);
        TokenBalanceOracle oracle = _installTokenBalanceOracle(_dao);


        _cacheDandelionApps(dandelionVoting, redemptions, tokenRequest, timeLock, delay, oracle);
    }

    function _setupPayrollApp(Kernel _dao, ACL _acl, Finance _finance, Voting _voting, uint256[4] memory _payrollSettings) internal {

        (address denominationToken, IFeed priceFeed, uint64 rateExpiryTime, address employeeManager) = _unwrapPayrollSettings(_payrollSettings);
        address manager = employeeManager == address(0) ? _voting : employeeManager;

        Payroll payroll = _installPayrollApp(_dao, _finance, denominationToken, priceFeed, rateExpiryTime);
        _createPayrollPermissions(_acl, payroll, manager, _voting, _voting);
        _grantCreatePaymentPermission(_acl, _finance, payroll);
    }

    /* REDEMPTIONS */

    function _installRedemptionsApp(Kernel _dao, address[] memory _redemptionsRedeemableTokens) internal returns (Redemptions) {

        (TokenManager tokenManager, Vault vault,) = _popBaseAppsCache();
        Redemptions redemptions = Redemptions(_registerApp(_dao, REDEMPTIONS_APP_ID));
        redemptions.initialize(vault, tokenManager, _redemptionsRedeemableTokens);
        return redemptions;
    }


    function _createRedemptionsPermissions(
        ACL _acl,
        Redemptions _redemptions,
        TokenManager _tokenManager,
        Vault _vault,
        Voting _voting,
        address _manager
    )
        internal
    {

        _acl.createPermission(ANY_ENTITY, _redemptions, _redemptions.REDEEM_ROLE(), _manager);
        _acl.createPermission(_voting, _redemptions, _redemptions.ADD_TOKEN_ROLE(), _manager);
        _acl.createPermission(_voting, _redemptions, _redemptions.REMOVE_TOKEN_ROLE(), _manager);
        _acl.grantPermission(_redemptions, _tokenManager, _tokenManager.BURN_ROLE());
        _acl.grantPermission(_redemptions, _vault, _vault.TRANSFER_ROLE());

    }


    /* TOKEN REQUEST */

    function _installTokenRequestApp(Kernel _dao, address[] memory _tokenRequestAcceptedDepositTokens) internal returns (TokenRequest) {

        (TokenManager tokenManager, Vault vault,) = _popBaseAppsCache();
        TokenRequest tokenRequest = TokenRequest(_registerApp(_dao, TOKEN_REQUEST_APP_ID));
        tokenRequest.initialize(tokenManager, vault, _tokenRequestAcceptedDepositTokens);
        return tokenRequest;
    }

    function _createTokenRequestPermissions(
        ACL _acl,
        TokenRequest _tokenRequest,
        TokenManager _tokenManager,
        Voting _voting,
        address _manager
    )
        internal
    {
        _acl.createPermission(_voting, _tokenRequest, _tokenRequest.SET_TOKEN_MANAGER_ROLE(), _manager);
        _acl.createPermission(_voting, _tokenRequest, _tokenRequest.SET_VAULT_ROLE(), _manager);
        _acl.createPermission(_voting, _tokenRequest, _tokenRequest.FINALISE_TOKEN_REQUEST_ROLE(), _manager);
        _acl.grantPermission(_tokenRequest, _tokenManager, _tokenManager.MINT_ROLE());

    }

    /* TIME LOCK */

    function _installTimeLockApp(Kernel _dao,  address _timeLockToken, uint256[3] memory _timeLockSettings) internal returns (TimeLock) {
        return _installTimeLockApp(_dao, _timeLockToken, _timeLockSettings[0], _timeLockSettings[1], _timeLockSettings[2]);
    }

    function _installTimeLockApp(
        Kernel _dao,
        address _timeLockToken,
        uint256 _lockDuration,
        uint256 _lockAmount,
        uint256 _spamPenaltyFactor
    )
        internal returns (TimeLock)
    {
        TimeLock timeLock = TimeLock(_registerApp(_dao, TIME_LOCK_APP_ID));
        uint256 adjustedAmount = _lockAmount * (10 ** uint256(ERC20Detailed(_timeLockToken).decimals()));
        timeLock.initialize(_timeLockToken, _lockDuration, adjustedAmount, _spamPenaltyFactor);
        return timeLock;
    }

    function _createTimeLockPermissions(
        ACL _acl,
        TimeLock _timeLock,
        Voting _voting,
        TokenBalanceOracle _tokenBalanceOracle,
        address _manager
    )
        internal
    {
        _acl.createPermission(_voting, _timeLock, _timeLock.CHANGE_DURATION_ROLE(), _manager);
        _acl.createPermission(_voting, _timeLock, _timeLock.CHANGE_AMOUNT_ROLE(), _manager);
        _acl.createPermission(_voting, _timeLock, _timeLock.CHANGE_SPAM_PENALTY_ROLE(), _manager);
        _acl.createPermission(ANY_ENTITY, _timeLock, _timeLock.LOCK_TOKENS_ROLE(), address(this));
        _setOracle(_acl, ANY_ENTITY, _timeLock, _timeLock.LOCK_TOKENS_ROLE(), _tokenBalanceOracle);

        //change manager
        _acl.setPermissionManager(_voting, _timeLock, _timeLock.LOCK_TOKENS_ROLE());

    }

    /* DELAY */

    function _installDelayApp(Kernel _dao, uint64 _executionDelay) internal returns (Delay) {

        Delay delay = Delay(_registerApp(_dao, DELAY_APP_ID));
        delay.initialize(_executionDelay);
        return delay;
    }

    function _createDelayPermissions(
        ACL _acl,
        Delay _delay,
        TokenManager _tokenManager,
        Voting _voting,
        address _manager
    )
        internal
    {
        _acl.createPermission(_voting, _delay, _delay.SET_DELAY_ROLE(), _manager);
        _acl.createPermission(_tokenManager, _delay, _delay.PAUSE_EXECUTION_ROLE(), _manager);
        _acl.createPermission(_tokenManager, _delay, _delay.RESUME_EXECUTION_ROLE(), _manager);
        _acl.createPermission(_tokenManager, _delay, _delay.CANCEL_EXECUTION_ROLE(), _manager);
        _acl.createPermission(_tokenManager, _delay, _delay.DELAY_EXECUTION_ROLE(), _manager);

    }

    /** TOKEN BALANCE ORACLE */

    function _installTokenBalanceOracle(Kernel _dao) internal returns (TokenBalanceOracle) {
        (TokenManager tokenManager,,) = _popBaseAppsCache();
        TokenBalanceOracle oracle = TokenBalanceOracle(_registerApp(_dao, TOKEN_BALANCE_ORACLE_APP_ID));
        oracle.initialize(tokenManager.token(), 1 * (10 ** uint256(TOKEN_DECIMALS)));
        return oracle;
    }

    function _createTokenBalanceOraclePermissions(
        ACL _acl,
        TokenBalanceOracle _oracle,
        Voting _voting,
        address _manager
    )
        internal
    {
        _acl.createPermission(_voting, _oracle, _oracle.SET_TOKEN_ROLE(), _manager);
        _acl.createPermission(_voting, _oracle, _oracle.SET_MIN_BALANCE_ROLE(), _manager);

    }

    function _setupBasePermissions(
        ACL _acl,
        bool _useAgentAsVault
    )
        internal
    {

        (TokenManager tokenManager, Vault agentOrVault, Finance finance) = _popBaseAppsCache();
        (Voting dandelionVoting,,,,,) = _popDandelionAppsCache();

        if (_useAgentAsVault) {
            _createAgentPermissions(_acl, Agent(agentOrVault), dandelionVoting, dandelionVoting);
        }
        _createVaultPermissions(_acl, agentOrVault, finance, address(this));
        _createFinancePermissions(_acl, finance, dandelionVoting, dandelionVoting);
        _createFinanceCreatePaymentsPermission(_acl, finance, dandelionVoting, address(this));
        _createTokenManagerPermissions(_acl, tokenManager, dandelionVoting,  address(this));
    }

    function _setupDandelionPermissions(ACL _acl) internal {

        (TokenManager tokenManager, Vault agentOrVault, Finance finance) = _popBaseAppsCache();
        (Voting dandelionVoting, Redemptions redemptions, TokenRequest tokenRequest, TimeLock timeLock, Delay delay, TokenBalanceOracle tokenBalanceOracle ) = _popDandelionAppsCache();

        _createVotingPermissions(_acl, dandelionVoting, dandelionVoting, tokenManager, dandelionVoting);
        _createRedemptionsPermissions(_acl, redemptions, tokenManager, agentOrVault, dandelionVoting, dandelionVoting);
        _createTokenRequestPermissions(_acl, tokenRequest, tokenManager, dandelionVoting, dandelionVoting);
        _createTimeLockPermissions(_acl, timeLock, dandelionVoting, tokenBalanceOracle, dandelionVoting);
        _createDelayPermissions(_acl, delay, tokenManager, dandelionVoting, dandelionVoting);
        _createTokenBalanceOraclePermissions(_acl, tokenBalanceOracle, dandelionVoting, dandelionVoting);
        _createEvmScriptsRegistryPermissions(_acl, dandelionVoting, dandelionVoting);

        _transferPermissionFromTemplate(_acl, tokenManager, dandelionVoting, tokenManager.MINT_ROLE(), dandelionVoting);
        _transferPermissionFromTemplate(_acl, tokenManager, dandelionVoting, tokenManager.BURN_ROLE(), dandelionVoting);
        _transferPermissionFromTemplate(_acl, agentOrVault, dandelionVoting, agentOrVault.TRANSFER_ROLE(), dandelionVoting);

    }

    function _cacheToken(MiniMeToken _token) internal {
        Cache storage c = cache[msg.sender];

        c.token = address(_token);
    }

    function _cacheBaseApps(Kernel _dao, TokenManager _tokenManager, Vault _vault, Finance _finance) internal {
        Cache storage c = cache[msg.sender];

        c.dao = address(_dao);
        c.tokenManager = address(_tokenManager);
        c.agentOrVault = address(_vault);
        c.finance = address(_finance);
    }

    function _cacheDandelionApps(Voting _dandelionVoting, Redemptions _redemptions, TokenRequest _tokenRequest, TimeLock _timeLock, Delay _delay, TokenBalanceOracle _tokenBalanceOracle) internal {
        Cache storage c = cache[msg.sender];
        require(c.dao != address(0), ERROR_MISSING_CACHE);

        c.dandelionVoting = address(_dandelionVoting);
        c.redemptions = address(_redemptions);
        c.tokenRequest = address(_tokenRequest);
        c.timeLock = address(_timeLock);
        c.delay = address(_delay);
        c.tokenBalanceOracle = address(_tokenBalanceOracle);
    }

    function _popTokenCache() internal returns (MiniMeToken) {
        Cache storage c = cache[msg.sender];
        require(c.token != address(0), ERROR_MISSING_TOKEN_CACHE);

        MiniMeToken token = MiniMeToken(c.token);
        return token;
    }

    function _popDaoCache() internal returns (Kernel dao) {
        Cache storage c = cache[msg.sender];
        require(c.dao != address(0), ERROR_MISSING_CACHE);

        dao = Kernel(c.dao);
    }

    function _popAgentAsVaultCache() internal returns (bool agentAsVault) {
        Cache storage c = cache[msg.sender];
        require(c.dao != address(0), ERROR_MISSING_CACHE);

        agentAsVault = c.agentAsVault;
    }

    function _popBaseAppsCache() internal returns (
        TokenManager tokenManager,
        Vault vault,
        Finance finance
    )
    {
        Cache storage c = cache[msg.sender];
        require(c.dao != address(0), ERROR_MISSING_CACHE);

        tokenManager = TokenManager(c.tokenManager);
        vault = Vault(c.agentOrVault);
        finance = Finance(c.finance);
    }

    function _popDandelionAppsCache() internal returns (
        /* TODO: CHANGE THIS FOR DANDELIONVOTING */
        Voting dandelionVoting,
        Redemptions redemptions,
        TokenRequest tokenRequest,
        TimeLock timeLock,
        Delay delay,
        TokenBalanceOracle tokenBalanceOracle
    )
    {
        Cache storage c = cache[msg.sender];
        require(c.dao != address(0), ERROR_MISSING_CACHE);

        //TODO change fot DandelionVoting type
        dandelionVoting = Voting(c.dandelionVoting);
        redemptions = Redemptions(c.redemptions);
        tokenRequest = TokenRequest(c.tokenRequest);
        timeLock = TimeLock(c.timeLock);
        delay = Delay(c.delay);
        tokenBalanceOracle = TokenBalanceOracle(c.tokenBalanceOracle);
    }

    function _clearCache() internal {
        Cache storage c = cache[msg.sender];
        require(c.dao != address(0), ERROR_MISSING_CACHE);

        delete c.dao;
        delete c.token;
        delete c.tokenManager;
        delete c.agentOrVault;
        delete c.finance;
        delete c.dandelionVoting;
        delete c.tokenRequest;
        delete c.redemptions;
        delete c.timeLock;
        delete c.delay;
        delete c.tokenBalanceOracle;
        delete c.agentAsVault;
    }

    function _ensureBaseAppsCache() internal {
        Cache storage c = cache[msg.sender];
        require(c.tokenManager != address(0), ERROR_MISSING_CACHE);
        require(c.agentOrVault != address(0), ERROR_MISSING_CACHE);
        require(c.finance != address(0), ERROR_MISSING_CACHE);
    }


    function _ensureBaseSettings(
        address[] memory _holders,
        uint256[] memory _stakes,
        uint256[4] memory _payrollSettings
    )
        private
        pure
    {
        _ensureBaseSettings(_holders, _stakes);
        require(_payrollSettings.length == 4, ERROR_BAD_PAYROLL_SETTINGS);
    }

    function _ensureBaseSettings(address[] memory _holders, uint256[] memory _stakes) private pure {
        require(_holders.length > 0, ERROR_EMPTY_HOLDERS);
        require(_holders.length == _stakes.length, ERROR_BAD_HOLDERS_STAKES_LEN);
    }

    function _ensureDandelionSettings(
        address[] memory _tokenRequestAcceptedDepositTokens,
        address _timeLockToken,
        uint256[3] memory _timeLockSettings,
        uint64[3] memory _votingSettings
    )
        private
    {
        require(_tokenRequestAcceptedDepositTokens.length > 0, ERROR_BAD_TOKENREQUEST_TOKEN_LIST);
        require(isContract(_timeLockToken), ERROR_TIMELOCK_TOKEN_NOT_CONTRACT);
        require(_timeLockSettings.length == 3, ERROR_BAD_TIMELOCK_SETTINGS);
        require(_votingSettings.length == 3, ERROR_BAD_VOTING_SETTINGS);
    }


    function _registerApp(Kernel _dao, bytes32 _appId) internal returns (address) {
        address proxy = _dao.newAppInstance(_appId, _latestVersionAppBase(_appId));
        emit InstalledApp(proxy, _appId);

        return proxy;
    }

    function _setOracle(ACL _acl, address _who, address _where, bytes32 _what, address _oracle) internal {
        uint256[] memory params = new uint256[](1);
        params[0] = _paramsTo256(ORACLE_PARAM_ID, uint8(Op.EQ), uint240(_oracle));

        _acl.grantPermissionP(_who, _where, _what, params);
    }

    function _paramsTo256(uint8 _id,uint8 _op, uint240 _value) internal returns (uint256) {
        return (uint256(_id) << 248) + (uint256(_op) << 240) + _value;
    }

}
