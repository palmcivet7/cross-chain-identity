// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface ICCIDRequest {
    function requestCcidStatus(
        uint256 _linkAmountToSend,
        address _ccidFulfill,
        address _requestedAddress,
        uint64 _chainSelector
    ) external returns (bytes32 messageId);
}
