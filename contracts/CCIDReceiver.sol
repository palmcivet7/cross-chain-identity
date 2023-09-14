// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./CCIPReceiver_Unsafe.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract CCIDReceiver is CCIPReceiver_Unsafe {
    event KYCStatusReceived(string status);

    constructor(address _router) CCIPReceiver_Unsafe(_router) {}

    function ccipReceive(Client.Any2EVMMessage memory message) external override {
        string memory status = abi.decode(message.data, (string));
        emit KYCStatusReceived(status);
    }
}
