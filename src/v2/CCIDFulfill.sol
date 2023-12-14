// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LinkTokenInterface} from "@chainlink-brownie-contracts/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {AutomationBase} from "@chainlink/contracts/src/v0.8/automation/AutomationBase.sol";
import {ILogAutomation, Log} from "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";

contract CCIDFulfill is Ownable, AutomationBase, CCIPReceiver {
    error CCIDFulfill__InvalidAddress();
    error CCIDFulfill__InvalidChainSelector();
    error CCIDFulfill__SourceChainNotAllowed(uint64 sourceChainSelector);
    error CCIDFulfill__SenderNotAllowed(address sender);

    event CCIDStatusRequested(address requestedAddress);
    event CCIDStatusFulfilled(address requestedAddress, IEverestConsumer.Status status, uint40 kycTimestamp);

    LinkTokenInterface public immutable i_link;
    IEverestConsumer public immutable i_consumer;
    address public immutable i_ccidRequest;
    uint64 public immutable i_chainSelector;

    mapping(uint64 chainSelector => bool isAllowlisted) public s_allowlistedSourceChains;
    mapping(address sender => bool isAllowlisted) public s_allowlistedSenders;
    mapping(address => bool) public s_pendingRequests;

    constructor(address _router, address _link, address _consumer, address _ccidRequest, uint64 _chainSelector)
        CCIPReceiver(_router)
    {
        if (_router == address(0)) revert CCIDFulfill__InvalidAddress();
        if (_link == address(0)) revert CCIDFulfill__InvalidAddress();
        if (_consumer == address(0)) revert CCIDFulfill__InvalidAddress();
        if (_ccidRequest == address(0)) revert CCIDFulfill__InvalidAddress();
        if (_chainSelector == 0) revert CCIDFulfill__InvalidChainSelector();
        i_link = LinkTokenInterface(_link);
        i_consumer = IEverestConsumer(_consumer);
        i_ccidRequest = _ccidRequest;
        i_chainSelector = _chainSelector;
        i_link.approve(address(i_router), type(uint256).max);
    }

    ///////////////////////////////
    ///////// Modifiers //////////
    /////////////////////////////

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!s_allowlistedSourceChains[_sourceChainSelector]) {
            revert CCIDFulfill__SourceChainNotAllowed(_sourceChainSelector);
        }
        if (!s_allowlistedSenders[_sender]) revert CCIDFulfill__SenderNotAllowed(_sender);
        _;
    }

    ///////////////////////////////
    /////////// CCIP /////////////
    /////////////////////////////

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

    function _ccipReceive(Client.Any2EVMMessage memory message)
        internal
        override
        onlyRouter
        onlyAllowlisted(message.sourceChainSelector, abi.decode(message.sender, (address)))
    {
        (address requestedAddress) = abi.decode(message.data, (address));
        s_pendingRequests[requestedAddress] = true;
        i_consumer.requestStatus(requestedAddress);
        emit CCIDStatusRequested(requestedAddress);
    }

    ///////////////////////////////
    ///////// Automation /////////
    /////////////////////////////

    function checkLog(Log calldata log, bytes memory /* checkData */ )
        external
        view
        cannotExecute
        returns (bool upkeepNeeded, bytes memory performData)
    {
        bytes32 eventSignature = keccak256("Fulfilled(bytes32,address,address,uint8,uint40)");
        if (log.source == address(i_consumer) && log.topics[0] == eventSignature) {
            (IEverestConsumer.Status status, uint40 kycTimestamp) =
                abi.decode(log.data, (IEverestConsumer.Status, uint40));
            address requestedAddress = bytes32ToAddress(log.topics[2]);
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

    function performUpkeep(bytes calldata performData) external {
        fulfillCcidRequest(performData);
    }

    ///////////////////////////////
    ///////// Setter /////////////
    /////////////////////////////

    function allowlistSourceChain(uint64 _sourceChainSelector, bool _allowed) external onlyOwner {
        s_allowlistedSourceChains[_sourceChainSelector] = _allowed;
    }

    function allowlistSender(address _sender, bool _allowed) external onlyOwner {
        s_allowlistedSenders[_sender] = _allowed;
    }

    ///////////////////////////////
    ///////// Utility ////////////
    /////////////////////////////

    function bytes32ToAddress(bytes32 _bytes) private pure returns (address) {
        return address(uint160(uint256(_bytes)));
    }
}
