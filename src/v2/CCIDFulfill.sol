// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LinkTokenInterface} from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {AutomationBase} from "@chainlink/contracts-ccip/src/v0.8/automation/AutomationBase.sol";
import {ILogAutomation, Log} from "@chainlink/contracts-ccip/src/v0.8/automation/interfaces/ILogAutomation.sol";
import {IAutomationRegistryConsumer} from
    "@chainlink/contracts-ccip/src/v0.8/automation/interfaces/IAutomationRegistryConsumer.sol";
import {IAutomationRegistrar, RegistrationParams} from "./interfaces/IAutomationRegistrar.sol";

/**
 * @title Cross-Chain Identity: Fulfill (CCIDFulfill)
 * @author palmcivet
 * @notice This contract is one of two in the CCID system. The other contract is CCIDRequest.
 * This is the contract that receives the cross-chain request for the identity status of an address,
 * and fulfills the request by sending it back to the CCIDRequest contract on the user's chain.
 */
contract CCIDFulfill is Ownable, AutomationBase, CCIPReceiver {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error CCIDFulfill__InvalidAddress();
    error CCIDFulfill__InvalidChainSelector();
    error CCIDFulfill__SourceChainNotAllowed(uint64 sourceChainSelector);
    error CCIDFulfill__SenderNotAllowed(address sender);
    error CCIDFulfill__OnlyForwarder();
    error CCIDFulfill__LinkTransferFailed();
    error CCIDFulfill__NoLinkToWithdraw();
    error CCIDFulfill__AutomationRegistrationFailed();
    error CCIDFulfill__NotEnoughLinkSent();

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    LinkTokenInterface internal immutable i_link;
    IEverestConsumer internal immutable i_everestConsumer;
    IAutomationRegistryConsumer internal immutable i_automationConsumer;
    address internal immutable i_ccidRequest;
    uint64 internal immutable i_chainSelector;
    uint256 internal immutable i_subId;

    address internal s_forwarderAddress;
    mapping(uint64 chainSelector => bool isAllowlisted) internal s_allowlistedSourceChains;
    mapping(address sender => bool isAllowlisted) internal s_allowlistedSenders;
    mapping(address => bool) internal s_pendingRequests;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CCIDStatusRequested(address indexed requestedAddress);
    event CCIDStatusFulfilled(
        address indexed requestedAddress, IEverestConsumer.Status indexed status, uint40 indexed kycTimestamp
    );
    event CCIDFulfill__AllowlistedSenderUpdated(address sender, bool allowed);
    event CCIDFulfill__AllowlistedSourceChainUpdated(uint64 sourceChainSelector, bool allowed);
    event CCIDFulfill__ForwarderContractSet(address forwarder);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!s_allowlistedSourceChains[_sourceChainSelector]) {
            revert CCIDFulfill__SourceChainNotAllowed(_sourceChainSelector);
        }
        if (!s_allowlistedSenders[_sender]) revert CCIDFulfill__SenderNotAllowed(_sender);
        _;
    }

    modifier revertIfZeroAddress(address _address) {
        if (_address == address(0)) revert CCIDFulfill__InvalidAddress();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev This contract is registered with Chainlink Automation when it is deployed and requires the
     *      deployer to hold LINK tokens in their wallet. Constructor is payable for cheaper deployment,
     *      but value is not intended to be sent.
     * @param _router - address of the CCIP router
     * @param _link - address of the LINK token
     * @param _consumer - address of the Everest Consumer contract
     * @param _automationConsumer - address of the Chainlink Automation Consumer contract
     * @param _automationRegistrar - address of the Chainlink Automation Registrar contract
     * @param _ccidRequest - address of the CCIDRequest contract on other chain
     * @param _chainSelector - CCIP destination chain selector of chain CCIDRequest is deployed on
     */
    constructor(
        address _router,
        address _link,
        address _consumer,
        address _automationConsumer,
        address _automationRegistrar,
        address _ccidRequest,
        uint64 _chainSelector
    )
        payable
        CCIPReceiver(_router)
        revertIfZeroAddress(_router)
        revertIfZeroAddress(_link)
        revertIfZeroAddress(_consumer)
        revertIfZeroAddress(_automationConsumer)
        revertIfZeroAddress(_automationRegistrar)
        revertIfZeroAddress(_ccidRequest)
    {
        if (_chainSelector == 0) revert CCIDFulfill__InvalidChainSelector();
        i_link = LinkTokenInterface(_link);
        i_everestConsumer = IEverestConsumer(_consumer);
        i_automationConsumer = IAutomationRegistryConsumer(_automationConsumer);
        i_ccidRequest = _ccidRequest;
        i_chainSelector = _chainSelector;
        i_link.approve(address(i_router), type(uint256).max);
        i_link.approve(address(i_everestConsumer), type(uint256).max);

        RegistrationParams memory params = RegistrationParams({
            name: "",
            encryptedEmail: hex"",
            upkeepContract: address(this),
            gasLimit: 2000000,
            adminAddress: owner(),
            triggerType: 0,
            checkData: hex"",
            triggerConfig: hex"",
            offchainConfig: hex"",
            amount: 1000000000000000000
        });
        i_link.approve(_automationRegistrar, params.amount);
        uint256 upkeepID = IAutomationRegistrar(_automationRegistrar).registerUpkeep(params);
        if (upkeepID == 0) revert CCIDFulfill__AutomationRegistrationFailed();
        i_subId = upkeepID;
    }

    /*//////////////////////////////////////////////////////////////
                                  CCIP
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice This function is called internally by Chainlink Automation with the fulfilled request data, sending it back to
     * the CCIDRequest contract on the source chain.
     * @param _fulfilledData Contains the requestedAddress, status, and kycTimestamp of a request.
     * @dev Sets the s_pendingRequests mapping for the requestedAddress to false, so the request will not be automatically
     * fulfilled again.
     */
    function fulfillCcidRequest(bytes calldata _fulfilledData) private {
        (address requestedAddress, IEverestConsumer.Status status, uint40 kycTimestamp) =
            abi.decode(_fulfilledData, (address, IEverestConsumer.Status, uint40));
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(i_ccidRequest),
            data: _fulfilledData,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(i_link)
        });
        s_pendingRequests[requestedAddress] = false;
        IRouterClient(i_router).ccipSend(i_chainSelector, message);
        emit CCIDStatusFulfilled(requestedAddress, status, kycTimestamp);
    }

    /**
     * @notice This uses Chainlink Automation's getMinBalance() function for "estimating" the price of the automation job.
     * If future versions of Automation include an equivalent to CCIP's getFees() function, that should be used instead.
     * @param _message The requestedAddress and LINK payment sent via CCIP
     * @dev The requestedAddress is mapped to true in s_pendingRequests.
     */
    function _ccipReceive(Client.Any2EVMMessage memory _message)
        internal
        override
        onlyRouter
        onlyAllowlisted(_message.sourceChainSelector, abi.decode(_message.sender, (address)))
    {
        uint256 receivedLink = _message.destTokenAmounts[0].amount;
        uint256 linkEverestPayment = i_everestConsumer.oraclePayment();
        uint96 linkAutomationPayment = i_automationConsumer.getMinBalance(i_subId);
        if (receivedLink < linkEverestPayment + uint256(linkAutomationPayment)) revert CCIDFulfill__NotEnoughLinkSent();

        if (!i_link.transfer(address(i_everestConsumer), linkEverestPayment)) revert CCIDFulfill__LinkTransferFailed();

        (address requestedAddress) = abi.decode(_message.data, (address));
        s_pendingRequests[requestedAddress] = true;

        i_automationConsumer.addFunds(i_subId, linkAutomationPayment);

        i_everestConsumer.requestStatus(requestedAddress);

        emit CCIDStatusRequested(requestedAddress);
    }

    /*//////////////////////////////////////////////////////////////
                               AUTOMATION
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Called continuously off-chain by Chainlink Automation nodes.
     * @param log Events emitted by EverestConsumer when requests are fulfilled.
     * @return upkeepNeeded Returns true if the fulfilled request is also mapped to true in s_pendingRequests.
     * @return performData Contains the requestedAddress, status, and kycTimestamp of a request.
     */
    function checkLog(Log calldata log, bytes memory /* checkData */ )
        external
        view
        cannotExecute
        returns (bool upkeepNeeded, bytes memory performData)
    {
        bytes32 eventSignature = keccak256("Fulfilled(bytes32,address,address,uint8,uint40)");
        if (log.source == address(i_everestConsumer) && log.topics[0] == eventSignature) {
            (address requestedAddress, IEverestConsumer.Status status, uint40 kycTimestamp) =
                abi.decode(log.data, (address, IEverestConsumer.Status, uint40));

            // address revealer = _bytes32ToAddress(log.topics[2]);

            if (s_pendingRequests[requestedAddress]) {
                performData = abi.encode(requestedAddress, status, kycTimestamp);
                upkeepNeeded = true;
            } else {
                upkeepNeeded = false;
            }
        } else {
            upkeepNeeded = false;
        }
    }

    /**
     * @notice Called by Chainlink Automation services and forwards the data to fulfillCcidRequest.
     * @param performData Contains the requestedAddress, status, and kycTimestamp of a request.
     */
    function performUpkeep(bytes calldata performData) external {
        if (msg.sender != s_forwarderAddress) revert CCIDFulfill__OnlyForwarder();
        fulfillCcidRequest(performData);
    }

    /*//////////////////////////////////////////////////////////////
                                WITHDRAW
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Function for withdrawing LINK tokens that can only be called by the owner.
     */
    function withdrawLink() external onlyOwner {
        uint256 balance = i_link.balanceOf(address(this));
        if (balance == 0) revert CCIDFulfill__NoLinkToWithdraw();
        if (!i_link.transfer(msg.sender, balance)) revert CCIDFulfill__LinkTransferFailed();
    }

    /*//////////////////////////////////////////////////////////////
                                 SETTER
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice CCIP best practices to prevent unwanted messages. Can only be set by the owner.
     * @param _sourceChainSelector CCIP Chain Selector of source chain the CCIDRequest contract is on.
     * @param _allowed Set to true to allow requests from a source chain.
     */
    function allowlistSourceChain(uint64 _sourceChainSelector, bool _allowed) external onlyOwner {
        s_allowlistedSourceChains[_sourceChainSelector] = _allowed;
        emit CCIDFulfill__AllowlistedSourceChainUpdated(_sourceChainSelector, _allowed);
    }

    /**
     * @notice CCIP best practices to prevent unwanted messages. Can only be set by the owner.
     * @param _sender CCIDRequest contract address.
     * @param _allowed Set to true to allow requests from CCIDRequest.
     */
    function allowlistSender(address _sender, bool _allowed) external onlyOwner {
        s_allowlistedSenders[_sender] = _allowed;
        emit CCIDFulfill__AllowlistedSenderUpdated(_sender, _allowed);
    }

    /**
     * @notice Prevents performUpkeep from being called by unwanted actors. Can only be set by the owner.
     * @param _forwarderAddress Chainlink Automation Forwarder contract address.
     */
    function setForwarderAddress(address _forwarderAddress) external onlyOwner {
        s_forwarderAddress = _forwarderAddress;
        emit CCIDFulfill__ForwarderContractSet(_forwarderAddress);
    }

    /*//////////////////////////////////////////////////////////////
                                UTILITY
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Utility function for decoding address in event logs. This is needed to check the requestedAddress by Chainlink's
     * off-chain Automation nodes in checkLog().
     * @param _bytes requestedAddress in the form of bytes32
     */
    function _bytes32ToAddress(bytes32 _bytes) private pure returns (address) {
        return address(uint160(uint256(_bytes)));
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    function getLink() external view returns (LinkTokenInterface) {
        return i_link;
    }

    function getEverestConsumer() external view returns (IEverestConsumer) {
        return i_everestConsumer;
    }

    function getCcidRequest() external view returns (address) {
        return i_ccidRequest;
    }

    function getChainSelector() external view returns (uint64) {
        return i_chainSelector;
    }

    function getPendingRequest(address _revealee) external view returns (bool) {
        return s_pendingRequests[_revealee];
    }
}
