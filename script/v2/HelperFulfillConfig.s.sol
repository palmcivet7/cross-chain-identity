// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Router} from "@chainlink/contracts-ccip/src/v0.8/ccip/Router.sol";
import {MockARM} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/mocks/MockARM.sol";
import {WETH9} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/WETH9.sol";
import {LinkToken} from "../../test/mocks/LinkToken.sol";
import {MockEverestConsumer} from "../../test/mocks/MockEverestConsumer.sol";
import {CCIDRequest} from "../../src/v2/CCIDRequest.sol";

contract HelperFulfillConfig is Script {
    struct NetworkConfig {
        address router;
        address link;
        address consumer;
        address ccidRequest;
        uint64 chainSelector;
        address mockArm;
    }

    NetworkConfig public activeNetworkConfig;

    uint64 public constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753; // Sepolia

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 5) {
            activeNetworkConfig = getGoerliEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            router: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59,
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            consumer: address(0),
            ccidRequest: address(0),
            chainSelector: 0,
            mockArm: address(0)
        });
    }

    function getGoerliEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            router: address(0), // not available on ccip
            link: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB,
            consumer: address(0),
            ccidRequest: address(0),
            chainSelector: 0,
            mockArm: address(0)
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        vm.startBroadcast();
        WETH9 weth9 = new WETH9();
        MockARM mockArm = new MockARM();
        Router router = new Router(address(weth9), address(mockArm));
        LinkToken mockLink = new LinkToken();
        MockEverestConsumer mockConsumer = new MockEverestConsumer();
        CCIDRequest ccidRequest = new CCIDRequest(address(router), address(mockLink));
        vm.stopBroadcast();

        return NetworkConfig({
            router: address(router),
            link: address(mockLink),
            consumer: address(mockConsumer),
            ccidRequest: address(ccidRequest),
            chainSelector: SEPOLIA_CHAIN_SELECTOR,
            mockArm: address(mockArm)
        });
    }
}
