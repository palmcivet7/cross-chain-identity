// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LinkTokenInterface} from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

contract CCIDRequest is Ownable, CCIPReceiver {
    error CCIDRequest__InvalidAddress();
    error CCIDRequest__DestinationChainNotAllowlisted(uint64 destinationChainSelector);
    error CCIDRequest__SourceChainNotAllowed(uint64 sourceChainSelector);
    error CCIDRequest__SenderNotAllowed(address sender);

    event CCIDStatusReceived(
        address indexed requestedAddress, IEverestConsumer.Status indexed status, uint40 indexed kycTimestamp
    );

    LinkTokenInterface public immutable i_link;

    mapping(uint64 chainSelector => bool isAllowlisted) public s_allowlistedDestinationChains;
    mapping(uint64 chainSelector => bool isAllowlisted) public s_allowlistedSourceChains;
    mapping(address sender => bool isAllowlisted) public s_allowlistedSenders;

    constructor(address _router, address _link) CCIPReceiver(_router) {
        if (_router == address(0)) revert CCIDRequest__InvalidAddress();
        if (_link == address(0)) revert CCIDRequest__InvalidAddress();
        i_link = LinkTokenInterface(_link);
        i_link.approve(address(i_router), type(uint256).max);
    }

    ///////////////////////////////
    ///////// Modifiers //////////
    /////////////////////////////

    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!s_allowlistedDestinationChains[_destinationChainSelector]) {
            revert CCIDRequest__DestinationChainNotAllowlisted(_destinationChainSelector);
        }
        _;
    }

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!s_allowlistedSourceChains[_sourceChainSelector]) {
            revert CCIDRequest__SourceChainNotAllowed(_sourceChainSelector);
        }
        if (!s_allowlistedSenders[_sender]) revert CCIDRequest__SenderNotAllowed(_sender);
        _;
    }

    ///////////////////////////////
    /////////// CCIP /////////////
    /////////////////////////////

    function requestCcidStatus(address _ccidFulfill, address _requestedAddress, uint64 _chainSelector)
        public
        onlyAllowlistedDestinationChain(_chainSelector)
    {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_ccidFulfill),
            data: abi.encode(_requestedAddress),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(i_link)
        });
        IRouterClient(i_router).ccipSend(_chainSelector, message);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message)
        internal
        override
        onlyRouter
        onlyAllowlisted(message.sourceChainSelector, abi.decode(message.sender, (address)))
    {
        (address requestedAddress, IEverestConsumer.Status status, uint40 kycTimestamp) =
            abi.decode(message.data, (address, IEverestConsumer.Status, uint40));
        emit CCIDStatusReceived(requestedAddress, status, kycTimestamp);
    }

    ///////////////////////////////
    /////////// Setter ///////////
    /////////////////////////////

    function allowlistDestinationChain(uint64 _destinationChainSelector, bool _allowed) external onlyOwner {
        s_allowlistedDestinationChains[_destinationChainSelector] = _allowed;
    }

    function allowlistSourceChain(uint64 _sourceChainSelector, bool _allowed) external onlyOwner {
        s_allowlistedSourceChains[_sourceChainSelector] = _allowed;
    }

    function allowlistSender(address _sender, bool _allowed) external onlyOwner {
        s_allowlistedSenders[_sender] = _allowed;
    }
}
