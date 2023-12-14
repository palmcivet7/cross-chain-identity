// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployCCIDReceiver} from "../../script/DeployCCIDReceiver.s.sol";
import {CCIDReceiver} from "../../src/v1/CCIDReceiver.sol";
import {HelperReceiverConfig} from "../../script/HelperReceiverConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {Router} from "@chainlink/contracts/src/v0.8/ccip/Router.sol";

contract CCIDReceiverTest is Test {
    CCIDReceiver ccidReceiver;
    HelperReceiverConfig helperConfig;
    Router router;

    uint16 public constant MAX_RET_BYTES = 4 + 4 * 32;

    function setUp() external {
        DeployCCIDReceiver deployer = new DeployCCIDReceiver();
        (ccidReceiver, helperConfig) = deployer.run();
        (address routerAddress,) = helperConfig.activeNetworkConfig();
        router = Router(routerAddress);
    }

    function testConstructorPropertiesSetCorrectly() public {
        assertNotEq(address(ccidReceiver), address(0));
        assertEq(ccidReceiver.getRouter(), address(router));
    }

    function test_ccipReceive() public {
        vm.startPrank(msg.sender);
        Router.OffRamp memory newOffRamp = Router.OffRamp({
            sourceChainSelector: 16015286601757825753, // Sepolia
            offRamp: msg.sender
        });
        Router.OffRamp[] memory newOffRampArray = new Router.OffRamp[](1);
        newOffRampArray[0] = newOffRamp;

        router.applyRampUpdates(new Router.OnRamp[](0), new Router.OffRamp[](0), newOffRampArray);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256(abi.encodePacked("testMessageId")),
            sourceChainSelector: 16015286601757825753, // Sepolia
            sender: abi.encode(msg.sender),
            data: abi.encode("HUMAN_AND_UNIQUE"),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        router.routeMessage(message, MAX_RET_BYTES, 2000000000000, address(ccidReceiver));
        vm.stopPrank();
    }
}
