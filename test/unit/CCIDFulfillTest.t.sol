// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployCCIDFulfill} from "../../script/v2/DeployCCIDFulfill.s.sol";
import {CCIDFulfill} from "../../src/v2/CCIDFulfill.sol";
import {HelperFulfillConfig} from "../../script/v2/HelperFulfillConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {EverestConsumer} from "@everest/contracts/EverestConsumer.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Router} from "@chainlink/contracts-ccip/src/v0.8/ccip/Router.sol";
import {LinkToken} from "../mocks/LinkToken.sol";
import {EVM2EVMOnRamp} from "@chainlink/contracts-ccip/src/v0.8/ccip/onRamp/EVM2EVMOnRamp.sol";
import {EVM2EVMOnRampSetup} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/onRamp/EVM2EVMOnRampSetup.t.sol";
import {MockARM} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/mocks/MockARM.sol";
import {IPriceRegistry} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IPriceRegistry.sol";
import {Internal} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Internal.sol";
import {CCIDRequest} from "../../src/v2/CCIDRequest.sol";
import {AutomationBase} from "@chainlink/contracts-ccip/src/v0.8/automation/AutomationBase.sol";
import {Log} from "@chainlink/contracts-ccip/src/v0.8/automation/interfaces/ILogAutomation.sol";

contract CCIDFulfillTest is Test, EVM2EVMOnRampSetup {
    CCIDFulfill ccidFulfill;
    HelperFulfillConfig helperConfig;
    Router router;
    LinkToken link;
    MockARM mockArm;
    EverestConsumer everestConsumer;
    CCIDRequest ccidRequest;

    address routerAddress;
    address linkAddress;
    address onRampAddress;
    address mockArmAddress;
    address priceRegistryAddress;
    address consumerAddress;
    address requestAddress;

    address public REVEALEE = makeAddr("REVEALEE");
    uint256 public constant STARTING_USER_BALANCE = 1000 ether;
    address public AUTOMATION = makeAddr("AUTOMATION");
    uint64 public SEPOLIA_CHAIN_SELECTOR = 16015286601757825753; // Sepolia
    uint16 public constant MAX_RET_BYTES = 4 + 4 * 32;

    function setUp() public override {
        DeployCCIDFulfill deployer = new DeployCCIDFulfill();
        (ccidFulfill, helperConfig) = deployer.run();
        (routerAddress, linkAddress, consumerAddress,,, requestAddress,, mockArmAddress) =
            helperConfig.activeNetworkConfig();
        router = Router(routerAddress);
        link = LinkToken(linkAddress);
        everestConsumer = EverestConsumer(consumerAddress);
        ccidRequest = CCIDRequest(requestAddress);

        EVM2EVMOnRampSetup.setUp();
        EVM2EVMOnRamp.FeeTokenConfigArgs[] memory feeTokenConfigArgs = new EVM2EVMOnRamp.FeeTokenConfigArgs[](1);
        feeTokenConfigArgs[0] = EVM2EVMOnRamp.FeeTokenConfigArgs({
            token: linkAddress,
            networkFeeUSDCents: 10,
            gasMultiplierWeiPerEth: 1e9,
            premiumMultiplierWeiPerEth: 1e9,
            enabled: true
        });
        EVM2EVMOnRamp onRamp = new EVM2EVMOnRamp(
            EVM2EVMOnRamp.StaticConfig({
                linkToken: linkAddress,
                chainSelector: SOURCE_CHAIN_ID,
                destChainSelector: SEPOLIA_CHAIN_SELECTOR,
                defaultTxGasLimit: GAS_LIMIT,
                maxNopFeesJuels: MAX_NOP_FEES_JUELS,
                prevOnRamp: address(0),
                armProxy: address(mockArmAddress)
            }),
            generateDynamicOnRampConfig(address(router), address(s_priceRegistry)),
            getTokensAndPools(s_sourceTokens, getCastedSourcePools()),
            rateLimiterConfig(),
            feeTokenConfigArgs,
            s_tokenTransferFeeConfigArgs,
            getNopsAndWeights()
        );
        onRampAddress = address(onRamp);

        Internal.TokenPriceUpdate[] memory tokenPriceUpdates = new Internal.TokenPriceUpdate[](1);
        tokenPriceUpdates[0] = Internal.TokenPriceUpdate({sourceToken: linkAddress, usdPerToken: 10000000000000000000});
        Internal.GasPriceUpdate[] memory gasPriceUpdates = new Internal.GasPriceUpdate[](1);
        gasPriceUpdates[0] =
            Internal.GasPriceUpdate({destChainSelector: SEPOLIA_CHAIN_SELECTOR, usdPerUnitGas: 500000000000000});
        Internal.PriceUpdates memory priceUpdates =
            Internal.PriceUpdates({tokenPriceUpdates: tokenPriceUpdates, gasPriceUpdates: gasPriceUpdates});
        IPriceRegistry(address(s_priceRegistry)).updatePrices(priceUpdates);
    }

    function test_constructor_sets_values_correctly() public {
        assertEq(address(router), ccidFulfill.getRouter());
        assertEq(address(link), address(ccidFulfill.i_link()));
        assertEq(address(everestConsumer), address(ccidFulfill.i_consumer()));
        assertEq(address(ccidRequest), address(ccidFulfill.i_ccidRequest()));
        assertEq(SEPOLIA_CHAIN_SELECTOR, ccidFulfill.i_chainSelector());
    }

    modifier applyRampUpdates() {
        vm.startPrank(msg.sender);
        Router.OnRamp memory newOnRamp =
            Router.OnRamp({destChainSelector: SEPOLIA_CHAIN_SELECTOR, onRamp: onRampAddress});
        Router.OnRamp[] memory newOnRampArray = new Router.OnRamp[](1);
        newOnRampArray[0] = newOnRamp;

        router.applyRampUpdates(newOnRampArray, new Router.OffRamp[](0), new Router.OffRamp[](0));
        vm.stopPrank();
        _;
    }

    modifier fundCcidFulfillAndApproveRouter() {
        vm.startPrank(msg.sender);
        link.transfer(address(ccidFulfill), STARTING_USER_BALANCE);
        vm.stopPrank();
        vm.startPrank(address(ccidFulfill));
        link.approve(address(router), type(uint256).max);
        vm.stopPrank();
        _;
    }

    function test_ccipReceive_reverts_if_source_chain_not_allowed() public {
        vm.startPrank(msg.sender);
        Router.OffRamp memory newOffRamp =
            Router.OffRamp({sourceChainSelector: SEPOLIA_CHAIN_SELECTOR, offRamp: msg.sender});
        Router.OffRamp[] memory newOffRampArray = new Router.OffRamp[](1);
        newOffRampArray[0] = newOffRamp;

        router.applyRampUpdates(new Router.OnRamp[](0), new Router.OffRamp[](0), newOffRampArray);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256(abi.encodePacked("testMessageId")),
            sourceChainSelector: SEPOLIA_CHAIN_SELECTOR,
            sender: abi.encode(address(ccidRequest)),
            data: abi.encode(REVEALEE, IEverestConsumer.Status.HumanAndUnique, 0),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        (bool success, bytes memory retData) =
            router.routeMessage(message, MAX_RET_BYTES, 2000000000000, address(ccidFulfill));

        assertFalse(success);

        if (!success) {
            bytes4 errorSignature =
                bytes4(retData[0]) | (bytes4(retData[1]) >> 8) | (bytes4(retData[2]) >> 16) | (bytes4(retData[3]) >> 24);
            assertEq(errorSignature, CCIDFulfill.CCIDFulfill__SourceChainNotAllowed.selector);

            bytes memory slicedRetData = new bytes(retData.length - 4);
            for (uint256 i = 4; i < retData.length; i++) {
                slicedRetData[i - 4] = retData[i];
            }
            uint64 sourceChainSelector = abi.decode(slicedRetData, (uint64));
            assertEq(sourceChainSelector, SEPOLIA_CHAIN_SELECTOR);
        }
        vm.stopPrank();
    }

    modifier approveSourceChain() {
        vm.startPrank(msg.sender);
        ccidFulfill.allowlistSourceChain(SEPOLIA_CHAIN_SELECTOR, true);
        vm.stopPrank();
        _;
    }

    function test_ccipReceive_reverts_if_source_sender_not_allowed() public approveSourceChain {
        vm.startPrank(msg.sender);
        Router.OffRamp memory newOffRamp =
            Router.OffRamp({sourceChainSelector: SEPOLIA_CHAIN_SELECTOR, offRamp: msg.sender});
        Router.OffRamp[] memory newOffRampArray = new Router.OffRamp[](1);
        newOffRampArray[0] = newOffRamp;

        router.applyRampUpdates(new Router.OnRamp[](0), new Router.OffRamp[](0), newOffRampArray);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256(abi.encodePacked("testMessageId")),
            sourceChainSelector: SEPOLIA_CHAIN_SELECTOR,
            sender: abi.encode(address(ccidRequest)),
            data: abi.encode(REVEALEE, IEverestConsumer.Status.HumanAndUnique, 0),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        (bool success, bytes memory retData) =
            router.routeMessage(message, MAX_RET_BYTES, 2000000000000, address(ccidFulfill));

        assertFalse(success);

        if (!success) {
            bytes4 errorSignature =
                bytes4(retData[0]) | (bytes4(retData[1]) >> 8) | (bytes4(retData[2]) >> 16) | (bytes4(retData[3]) >> 24);
            assertEq(errorSignature, CCIDFulfill.CCIDFulfill__SenderNotAllowed.selector);

            bytes memory slicedRetData = new bytes(retData.length - 4);
            for (uint256 i = 4; i < retData.length; i++) {
                slicedRetData[i - 4] = retData[i];
            }
            address sender = abi.decode(slicedRetData, (address));
            assertEq(sender, address(ccidRequest));
        }
        vm.stopPrank();
    }

    modifier approveSourceSender() {
        vm.startPrank(msg.sender);
        ccidFulfill.allowlistSender(address(ccidRequest), true);
        vm.stopPrank();
        _;
    }

    function test_ccipReceive_works() public approveSourceChain approveSourceSender {
        vm.startPrank(msg.sender);
        Router.OffRamp memory newOffRamp =
            Router.OffRamp({sourceChainSelector: SEPOLIA_CHAIN_SELECTOR, offRamp: msg.sender});
        Router.OffRamp[] memory newOffRampArray = new Router.OffRamp[](1);
        newOffRampArray[0] = newOffRamp;

        router.applyRampUpdates(new Router.OnRamp[](0), new Router.OffRamp[](0), newOffRampArray);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256(abi.encodePacked("testMessageId")),
            sourceChainSelector: SEPOLIA_CHAIN_SELECTOR,
            sender: abi.encode(address(ccidRequest)),
            data: abi.encode(REVEALEE, IEverestConsumer.Status.HumanAndUnique, 0),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        router.routeMessage(message, MAX_RET_BYTES, 2000000000000, address(ccidFulfill));
        vm.stopPrank();

        assertEq(ccidFulfill.s_pendingRequests(REVEALEE), true);
    }

    function test_checkLog_cannot_execute() public {
        Log memory log = Log({
            index: 0,
            timestamp: block.timestamp,
            txHash: 0x0,
            blockNumber: block.number,
            blockHash: blockhash(block.number - 1),
            source: address(0),
            topics: new bytes32[](0),
            data: new bytes(0)
        });
        bytes memory dummyBytes = new bytes(0);

        vm.startPrank(msg.sender);
        vm.expectRevert(AutomationBase.OnlySimulatedBackend.selector);
        ccidFulfill.checkLog(log, dummyBytes);
        vm.stopPrank();
    }

    modifier forwarderAddressSet() {
        vm.startPrank(msg.sender);
        ccidFulfill.setForwarderAddress(AUTOMATION);
        vm.stopPrank();
        _;
    }

    function test_performUpkeep_reverts_if_not_forwarder() public {
        vm.startPrank(msg.sender);
        bytes memory performData = abi.encode(REVEALEE, IEverestConsumer.Status.HumanAndUnique, 0);
        vm.expectRevert(CCIDFulfill.CCIDFulfill__OnlyForwarder.selector);
        ccidFulfill.performUpkeep(performData);
        vm.stopPrank();
    }

    function test_performUpkeep_works_and_fulfills_ccid_request()
        public
        forwarderAddressSet
        applyRampUpdates
        fundCcidFulfillAndApproveRouter
    {
        vm.startPrank(AUTOMATION);
        bytes memory performData = abi.encode(REVEALEE, IEverestConsumer.Status.HumanAndUnique, 0);
        ccidFulfill.performUpkeep(performData);
        vm.stopPrank();

        assertEq(ccidFulfill.s_pendingRequests(REVEALEE), false);
    }
}
