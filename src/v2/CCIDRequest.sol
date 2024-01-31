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
    error CCIDRequest__LinkTransferFailed();

    event CCIDStatusReceived(
        address indexed requestedAddress, IEverestConsumer.Status indexed status, uint40 indexed kycTimestamp
    );

    LinkTokenInterface public immutable i_link;

    mapping(uint64 chainSelector => bool isAllowlisted) public s_allowlistedDestinationChains;
    mapping(uint64 chainSelector => bool isAllowlisted) public s_allowlistedSourceChains;
    mapping(address sender => bool isAllowlisted) public s_allowlistedSenders;

    /**
     * @param _router Address of the CCIP Router contract.
     * @param _link Address of the LINK token.
     */
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

    /**
     * @dev This is how the user requests an identity status and is the only function in the entire protocol
     * the user needs to interact with.
     * @param _linkAmountToSend Amount of LINK to send across chain to pay for Automation and the Oracle Request.
     * This amount does NOT include the CCIP fee, which will also be taken when a user interacts with this function.
     * Since we can't calculate the exact amount for the other chain services, the transaction on the other chain
     * will revert if not enough is sent to cover the costs.
     * @param _ccidFulfill Address of CCIDFulfill contract on the chain the Everest consumer is on.
     * @param _requestedAddress Address who's identity status is being queried.
     * @param _chainSelector CCIP Destination Chain Selector of the chain the CCIDFulfill contract is on.
     */
    function requestCcidStatus(
        uint256 _linkAmountToSend,
        address _ccidFulfill,
        address _requestedAddress,
        uint64 _chainSelector
    ) public onlyAllowlistedDestinationChain(_chainSelector) returns (bytes32 messageId) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(i_link), amount: _linkAmountToSend});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_ccidFulfill),
            data: abi.encode(_requestedAddress),
            tokenAmounts: tokenAmounts,
            extraArgs: "",
            feeToken: address(i_link)
        });

        uint256 fees = IRouterClient(i_router).getFee(_chainSelector, message);
        uint256 linkToPay = fees + _linkAmountToSend;

        if (!i_link.transferFrom(msg.sender, address(this), linkToPay)) revert CCIDRequest__LinkTransferFailed();
        messageId = IRouterClient(i_router).ccipSend(_chainSelector, message);
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
