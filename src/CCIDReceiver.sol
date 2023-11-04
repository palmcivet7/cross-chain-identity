// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract CCIDReceiver is CCIPReceiver {
    event KYCStatusReceived(string status);

    constructor(address _router) CCIPReceiver(_router) {}

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        string memory status = abi.decode(message.data, (string));
        emit KYCStatusReceived(status);
    }
}
