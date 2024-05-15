// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";

contract MockEverestConsumer {
    error EverestConsumer__RevealeeShouldNotBeZeroAddress();

    event Fulfilled(
        bytes32 _requestId,
        address indexed _revealer,
        address indexed _revealee,
        IEverestConsumer.Status _status,
        uint40 _kycTimestamp
    );

    mapping(address revealee => IEverestConsumer.Status status) preSetStatus;
    mapping(address revealee => uint40 kycTimestamp) preSetKycTimestamp;

    function requestStatus(address _revealee) external {
        if (_revealee == address(0)) {
            revert EverestConsumer__RevealeeShouldNotBeZeroAddress();
        }

        emit Fulfilled(
            bytes32(uint256(uint160(_revealee))),
            msg.sender,
            _revealee,
            preSetStatus[_revealee],
            preSetKycTimestamp[_revealee]
        );
    }

    function setRevealeeStatus(address _revealee, IEverestConsumer.Status _status) public {
        preSetStatus[_revealee] = _status;
        if (_status == IEverestConsumer.Status.KYCUser) preSetKycTimestamp[_revealee] = uint40(block.timestamp);
        preSetKycTimestamp[_revealee] = 0;
    }

    /////////////////////////

    uint256 private s_oraclePayment = 1e17;

    function oraclePayment() external view returns (uint256 price) {
        return s_oraclePayment;
    }

    function setOraclePayment(uint256 _oraclePayment) external {
        s_oraclePayment = _oraclePayment;
    }
}
