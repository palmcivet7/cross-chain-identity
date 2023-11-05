// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Router} from "@chainlink/contracts/src/v0.8/ccip/Router.sol";
import {MockARM} from "@chainlink/contracts/src/v0.8/ccip/test/mocks/MockARM.sol";
import {WETH9} from "@chainlink/contracts/src/v0.8/ccip/test/WETH9.sol";

contract HelperReceiverConfig is Script {
    struct NetworkConfig {
        address router;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 5) {
            activeNetworkConfig = getGoerliEthConfig();
        } else if (block.chainid == 43113) {
            activeNetworkConfig = getFujiConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            router: 0xD0daae2231E9CB96b94C8512223533293C3693Bf, // https://docs.chain.link/ccip/supported-networks#ethereum-sepolia
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getGoerliEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            router: 0x0000000000000000000000000000000000000000, // Eth Goerli not available on CCIP
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getFujiConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            router: 0x554472a2720E5E7D5D3C817529aBA05EEd5F82D8, // https://docs.chain.link/ccip/supported-networks#avalanche-fuji
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        vm.startBroadcast();
        WETH9 weth9 = new WETH9();
        MockARM mockArm = new MockARM();
        Router router = new Router(address(weth9), address(mockArm));
        vm.stopBroadcast();

        return NetworkConfig({router: address(router), deployerKey: vm.envUint("ANVIL_PRIVATE_KEY")});
    }
}
