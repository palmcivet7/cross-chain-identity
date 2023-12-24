// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {CCIDRequest} from "../../src/v2/CCIDRequest.sol";
import {HelperRequestConfig} from "./HelperRequestConfig.s.sol";

contract DeployCCIDRequest is Script {
    function run() external returns (CCIDRequest, HelperRequestConfig) {
        HelperRequestConfig config = new HelperRequestConfig();
        (address router, address link) = config.activeNetworkConfig();

        vm.startBroadcast();
        CCIDRequest ccidRequest = new CCIDRequest(router, link);
        vm.stopBroadcast();
        return (ccidRequest, config);
    }
}
