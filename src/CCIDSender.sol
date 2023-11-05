// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {EverestConsumer} from "@everest/contracts/EverestConsumer.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CCIDSender is Ownable, EverestConsumer {
    address public router;
    address public link;
    address public ccidReceiver;
    uint64 public ccidDestinationSelector;

    constructor(
        address _router,
        address _link,
        address _oracle,
        string memory _jobId,
        uint256 _oraclePayment,
        string memory _signUpURL
    ) EverestConsumer(_link, _oracle, _jobId, _oraclePayment, _signUpURL) {
        router = _router;
        link = _link;
    }

    function fulfill(bytes32 _requestId, Status _status, uint40 _kycTimestamp)
        public
        override
        recordChainlinkFulfillment(_requestId)
    {
        super.fulfill(_requestId, _status, _kycTimestamp);
        sendKycStatusToCcidReceiver(_status);
    }

    function sendKycStatusToCcidReceiver(Status _status) internal {
        string memory statusString = statusToString(_status);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(ccidReceiver),
            data: abi.encode(statusString),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: link
        });
        IRouterClient(router).ccipSend(ccidDestinationSelector, message);
    }

    function setCcidReceiver(address _ccidReceiver) public onlyOwner {
        ccidReceiver = _ccidReceiver;
    }

    function setCcidDestinationSelector(uint64 _ccidDestinationSelector) public onlyOwner {
        ccidDestinationSelector = _ccidDestinationSelector;
    }
}
