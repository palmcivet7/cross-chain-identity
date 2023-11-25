// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {EverestConsumer} from "@everest/contracts/EverestConsumer.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LinkTokenInterface} from "@chainlink-brownie-contracts/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

contract CCIDSender is Ownable, EverestConsumer {
    error CCIDSender__KycTimestampShouldNotBeZeroForKycUser();
    error CCIDSender__KycTimestampShouldBeZeroForNonKycUser();

    address public immutable i_router;
    address public immutable i_link;
    address public s_ccidReceiver;
    uint64 public s_ccidDestinationSelector;

    constructor(
        address _router,
        address _link,
        address _oracle,
        string memory _jobId,
        uint256 _oraclePayment,
        string memory _signUpURL
    ) EverestConsumer(_link, _oracle, _jobId, _oraclePayment, _signUpURL) {
        i_router = _router;
        i_link = _link;
        LinkTokenInterface(i_link).approve(address(i_router), type(uint256).max);
    }

    function fulfill(bytes32 _requestId, Status _status, uint40 _kycTimestamp)
        external
        override
        recordChainlinkFulfillment(_requestId)
    {
        if (_status == Status.KYCUser) {
            if (_kycTimestamp == 0) {
                revert CCIDSender__KycTimestampShouldNotBeZeroForKycUser();
            }
        } else {
            if (_kycTimestamp != 0) {
                revert CCIDSender__KycTimestampShouldBeZeroForNonKycUser();
            }
        }

        Request storage request = _requests[_requestId];
        request.kycTimestamp = _kycTimestamp;
        request.isFulfilled = true;
        request.isHumanAndUnique = _status != Status.NotFound;
        request.isKYCUser = _status == Status.KYCUser;
        latestFulfilledRequestId[request.revealee] = _requestId;

        emit Fulfilled(_requestId, request.revealer, request.revealee, _status, _kycTimestamp);
        sendKycStatusToCcidReceiver(_status);
    }

    function sendKycStatusToCcidReceiver(Status _status) internal {
        string memory statusString = statusToString(_status);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(s_ccidReceiver),
            data: abi.encode(statusString),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: i_link
        });
        IRouterClient(i_router).ccipSend(s_ccidDestinationSelector, message);
    }

    function setCcidReceiver(address _ccidReceiver) public onlyOwner {
        s_ccidReceiver = _ccidReceiver;
    }

    function setCcidDestinationSelector(uint64 _ccidDestinationSelector) public onlyOwner {
        s_ccidDestinationSelector = _ccidDestinationSelector;
    }
}
