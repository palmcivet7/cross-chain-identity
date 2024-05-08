// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LinkTokenInterface} from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {ICCIDRequest} from "./interfaces/ICCIDRequest.sol";

/**
 * @title Cross-Chain Identity: Request (CCIDRequest)
 * @author palmcivet
 * @notice This contract is one of two in the CCID system. The other contract is CCIDFulfill.
 * This is the contract the user interacts with to make a cross-chain request for the identity status of an address.
 * Fulfilled requests are sent back to this contract.
 */
contract CCIDRequest is Ownable, CCIPReceiver, ICCIDRequest {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error CCIDRequest__InvalidAddress();
    error CCIDRequest__AmountMustBeMoreThanZero();
    error CCIDRequest__DestinationChainNotAllowlisted(uint64 destinationChainSelector);
    error CCIDRequest__SourceChainNotAllowed(uint64 sourceChainSelector);
    error CCIDRequest__SenderNotAllowed(address sender);
    error CCIDRequest__LinkTransferFailed();

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    LinkTokenInterface internal immutable i_link;

    mapping(uint64 chainSelector => bool isAllowlisted) internal s_allowlistedDestinationChains;
    mapping(uint64 chainSelector => bool isAllowlisted) internal s_allowlistedSourceChains;
    mapping(address sender => bool isAllowlisted) internal s_allowlistedSenders;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CCIDStatusRequested(bytes32 indexed messageId, address indexed requestedAddress, uint256 linkAmountSent);
    event CCIDStatusReceived(
        address indexed requestedAddress, IEverestConsumer.Status indexed status, uint40 indexed kycTimestamp
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
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

    modifier revertIfZeroAddress(address _address) {
        if (_address == address(0)) revert CCIDRequest__InvalidAddress();
        _;
    }

    modifier revertIfZeroAmount(uint256 _amount) {
        if (_amount == 0) revert CCIDRequest__AmountMustBeMoreThanZero();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Constructor is payable for cheaper deployment, but value is not intended to be sent.
     * @param _router Address of the CCIP Router contract.
     * @param _link Address of the LINK token.
     */
    constructor(address _router, address _link)
        payable
        CCIPReceiver(_router)
        revertIfZeroAddress(_router)
        revertIfZeroAddress(_link)
    {
        i_link = LinkTokenInterface(_link);
        i_link.approve(address(i_router), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                                  CCIP
    //////////////////////////////////////////////////////////////*/
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
    )
        external
        revertIfZeroAmount(_linkAmountToSend)
        revertIfZeroAddress(_ccidFulfill)
        revertIfZeroAddress(_requestedAddress)
        onlyAllowlistedDestinationChain(_chainSelector)
        returns (bytes32 messageId)
    {
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

        emit CCIDStatusRequested(messageId, _requestedAddress, _linkAmountToSend);
    }

    /**
     * @notice Receives CCIP messages and can only be called by the CCIP Router contract.
     * @param _message CCIP message containing requestedAddress, status, and kycTimestamp.
     */
    function _ccipReceive(Client.Any2EVMMessage memory _message)
        internal
        override
        onlyRouter
        onlyAllowlisted(_message.sourceChainSelector, abi.decode(_message.sender, (address)))
    {
        (address requestedAddress, IEverestConsumer.Status status, uint40 kycTimestamp) =
            abi.decode(_message.data, (address, IEverestConsumer.Status, uint40));
        emit CCIDStatusReceived(requestedAddress, status, kycTimestamp);
    }

    /*//////////////////////////////////////////////////////////////
                                 SETTER
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice CCIP best practices to prevent unwanted messages. Can only be set by the owner.
     * @param _destinationChainSelector CCIP Chain Selector of destination chain the CCIDFulfill contract is on.
     * @param _allowed Set to true to allow requests to destination chain.
     */
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool _allowed) external onlyOwner {
        s_allowlistedDestinationChains[_destinationChainSelector] = _allowed;
    }

    /**
     * @notice CCIP best practices to prevent unwanted messages. Can only be set by the owner.
     * @param _sourceChainSelector CCIP Chain Selector of source chain the CCIDFulfill contract is on.
     * @param _allowed Set to true to allow fulfilled requests from source chain.
     */
    function allowlistSourceChain(uint64 _sourceChainSelector, bool _allowed) external onlyOwner {
        s_allowlistedSourceChains[_sourceChainSelector] = _allowed;
    }

    /**
     * @notice CCIP best practices to prevent unwanted messages. Can only be set by the owner.
     * @param _sender CCIDFulfill contract address.
     * @param _allowed Set to true to allow fulfilled requests from CCIDFulfill.
     */
    function allowlistSender(address _sender, bool _allowed) external onlyOwner {
        s_allowlistedSenders[_sender] = _allowed;
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    function getLink() external view returns (LinkTokenInterface) {
        return i_link;
    }
}
