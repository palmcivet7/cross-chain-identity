// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.19;

// import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
// import {IPriceRegistry} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IPriceRegistry.sol";
// import {Internal} from "@chainlink/contracts/src/v0.8/ccip/libraries/Internal.sol";
// import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
// import {EnumerableMapAddresses} from "@chainlink/contracts/src/v0.8/shared/enumerable/EnumerableMapAddresses.sol";
// import {USDPriceWith18Decimals} from "@chainlink/contracts/src/v0.8/ccip/libraries/USDPriceWith18Decimals.sol";

// contract OnRamp {
//     using USDPriceWith18Decimals for uint224;

//     error InvalidChainSelector(uint64 chainSelector);
//     error NotAFeeToken(address token);
//     error InvalidExtraArgsTag();
//     error MessageTooLarge(uint256 maxSize, uint256 actualSize);
//     error MessageGasLimitTooHigh();
//     error UnsupportedNumberOfTokens();
//     error UnsupportedToken(IERC20 token);

//     uint64 internal immutable i_destChainSelector;
//     /// @dev Default gas limit for a transactions that did not specify
//     /// a gas limit in the extraArgs.
//     uint64 internal immutable i_defaultTxGasLimit;

//     /// @dev The config for the onRamp
//     DynamicConfig internal s_dynamicConfig;

//     /// @dev Struct to hold the execution fee configuration for a fee token
//     struct FeeTokenConfig {
//         uint32 networkFeeUSDCents; // ─────────╮ Flat network fee to charge for messages,  multiples of 0.01 USD
//         uint64 gasMultiplierWeiPerEth; //      │ Multiplier for gas costs, 1e18 based so 11e17 = 10% extra cost.
//         uint64 premiumMultiplierWeiPerEth; //  │ Multiplier for fee-token-specific premiums
//         bool enabled; // ──────────────────────╯ Whether this fee token is enabled
//     }

//     /// @dev Struct to contains the dynamic configuration
//     struct DynamicConfig {
//         address router; // ──────────────────────────╮ Router address
//         uint16 maxNumberOfTokensPerMsg; //           │ Maximum number of distinct ERC20 token transferred per message
//             // uint32 destGasOverhead; //                   │ Gas charged on top of the gasLimit to cover destination chain costs
//             // uint16 destGasPerPayloadByte; //             │ Destination chain gas charged for passing each byte of `data` payload to receiver
//             // uint32 destDataAvailabilityOverheadGas; // ──╯ Extra data availability gas charged on top of the message, e.g. for OCR
//             // uint16 destGasPerDataAvailabilityByte; // ───╮ Amount of gas to charge per byte of message data that needs availability
//             // uint16 destDataAvailabilityMultiplierBps; // │ Multiplier for data availability gas, multiples of bps, or 0.0001
//             // address priceRegistry; //                    │ Price registry address
//             // uint32 maxDataBytes; //                      │ Maximum payload data size in bytes
//             // uint32 maxPerMsgGasLimit; // ────────────────╯ Maximum gas limit for messages targeting EVMs
//     }

//     /// @dev Struct to hold the transfer fee configuration for token transfers
//     struct TokenTransferFeeConfig {
//         uint32 minFeeUSDCents; // ────╮ Minimum fee to charge per token transfer, multiples of 0.01 USD
//         uint32 maxFeeUSDCents; //     │ Maximum fee to charge per token transfer, multiples of 0.01 USD
//         uint16 deciBps; //            │ Basis points charged on token transfers, multiples of 0.1bps, or 1e-5
//         uint32 destGasOverhead; //    │ Gas charged to execute the token transfer on the destination chain
//         uint32 destBytesOverhead; // ─╯ Extra data availability bytes on top of fixed transfer data, including sourceTokenData and offchainData
//     }

//     /// @dev The execution fee token config that can be set by the owner or fee admin
//     mapping(address token => FeeTokenConfig feeTokenConfig) internal s_feeTokenConfig;
//     /// @dev The token transfer fee config that can be set by the owner or fee admin
//     mapping(address token => TokenTransferFeeConfig tranferFeeConfig) internal s_tokenTransferFeeConfig;

//     /// @dev source token => token pool
//     EnumerableMapAddresses.AddressToAddressMap private s_poolsBySourceToken;

//     //////////////////////////////////////////
//     ///////// constructor ///////////////////
//     ////////////////////////////////////////

//     constructor(address _router) {
//         i_destChainSelector = 16015286601757825753;
//         i_defaultTxGasLimit = 200000000000;
//         s_dynamicConfig.push(DynamicConfig({router: _router, maxNumberOfTokensPerMsg: 0}));
//         // destGasOverhead: ,
//         // destGasPerPayloadByte: ,
//         // destDataAvailabilityOverheadGas: ,
//         // destGasPerDataAvailabilityByte: ,
//         // destDataAvailabilityMultiplierBps: ,
//         // priceRegistry: ,
//         // maxDataBytes: ,
//         // destBytesOverhead: ,
//     }

//     /// @dev getFee MUST revert if the feeToken is not listed in the fee token config, as the router assumes it does.
//     /// @param destChainSelector The destination chain selector.
//     /// @param message The message to get quote for.
//     /// @return feeTokenAmount The amount of fee token needed for the fee, in smallest denomination of the fee token.
//     function getFee(uint64 destChainSelector, Client.EVM2AnyMessage calldata message)
//         external
//         view
//         returns (uint256 feeTokenAmount)
//     {
//         if (destChainSelector != i_destChainSelector) revert InvalidChainSelector(destChainSelector);

//         uint256 gasLimit = _fromBytes(message.extraArgs).gasLimit;
//         // Validate the message with various checks
//         _validateMessage(message.data.length, gasLimit, message.tokenAmounts.length);

//         FeeTokenConfig memory feeTokenConfig = s_feeTokenConfig[message.feeToken];
//         if (!feeTokenConfig.enabled) revert NotAFeeToken(message.feeToken);

//         (uint224 feeTokenPrice, uint224 packedGasPrice) =
//             IPriceRegistry(s_dynamicConfig.priceRegistry).getTokenAndGasPrices(message.feeToken, destChainSelector);
//         uint112 executionGasPrice = uint112(packedGasPrice);

//         // Calculate premiumFee in USD with 18 decimals precision first.
//         // If message-only and no token transfers, a flat network fee is charged.
//         // If there are token transfers, premiumFee is calculated from token transfer fee.
//         // If there are both token transfers and message, premiumFee is only calculated from token transfer fee.
//         uint256 premiumFee = 0;
//         uint32 tokenTransferGas = 0;
//         uint32 tokenTransferBytesOverhead = 0;
//         if (message.tokenAmounts.length > 0) {
//             (premiumFee, tokenTransferGas, tokenTransferBytesOverhead) =
//                 _getTokenTransferCost(message.feeToken, feeTokenPrice, message.tokenAmounts);
//         } else {
//             // Convert USD cents with 2 decimals to 18 decimals.
//             premiumFee = uint256(feeTokenConfig.networkFeeUSDCents) * 1e16;
//         }

//         // Apply a feeToken-specific multiplier with 18 decimals, raising the premiumFee to 36 decimals
//         premiumFee = premiumFee * feeTokenConfig.premiumMultiplierWeiPerEth;

//         // Calculate execution gas fee on destination chain in USD with 36 decimals.
//         // We add the message gas limit, the overhead gas, and the data availability gas together.
//         // We then multiply this destination gas total with the gas multiplier and convert it into USD.
//         uint256 executionCost = executionGasPrice
//             * (
//                 (
//                     gasLimit + s_dynamicConfig.destGasOverhead
//                         + (message.data.length * s_dynamicConfig.destGasPerPayloadByte) + tokenTransferGas
//                 ) * feeTokenConfig.gasMultiplierWeiPerEth
//             );

//         // Calculate data availability cost in USD with 36 decimals.
//         uint256 dataAvailabilityCost = 0;
//         // Only calculate data availability cost if data availability multiplier is non-zero.
//         // The multiplier should be set to 0 if destination chain does not charge data availability cost.
//         if (s_dynamicConfig.destDataAvailabilityMultiplierBps > 0) {
//             uint112 dataAvailabilityGasPrice = uint112(packedGasPrice >> Internal.GAS_PRICE_BITS);

//             dataAvailabilityCost = _getDataAvailabilityCost(
//                 dataAvailabilityGasPrice, message.data.length, message.tokenAmounts.length, tokenTransferBytesOverhead
//             );
//         }

//         // Calculate number of fee tokens to charge.
//         // Total USD fee is in 36 decimals, feeTokenPrice is in 18 decimals USD for 1e18 smallest token denominations.
//         // Result of the division is the number of smallest token denominations.
//         return (premiumFee + executionCost + dataAvailabilityCost) / feeTokenPrice;
//     }

//     /// @dev Convert the extra args bytes into a struct
//     /// @param extraArgs The extra args bytes
//     /// @return The extra args struct
//     function _fromBytes(bytes calldata extraArgs) internal view returns (Client.EVMExtraArgsV1 memory) {
//         if (extraArgs.length == 0) {
//             return Client.EVMExtraArgsV1({gasLimit: i_defaultTxGasLimit});
//         }
//         if (bytes4(extraArgs) != Client.EVM_EXTRA_ARGS_V1_TAG) revert InvalidExtraArgsTag();
//         // EVMExtraArgsV1 originally included a second boolean (strict) field which we have deprecated entirely.
//         // Clients may still send that version but it will be ignored.
//         return abi.decode(extraArgs[4:], (Client.EVMExtraArgsV1));
//     }

//     /// @notice Validate the forwarded message with various checks.
//     /// @dev This function can be called multiple times during a CCIPSend,
//     /// only common user-driven mistakes are validated here to minimize duplicate validation cost.
//     /// @param dataLength The length of the data field of the message.
//     /// @param gasLimit The gasLimit set in message for destination execution.
//     /// @param numberOfTokens The number of tokens to be sent.
//     function _validateMessage(uint256 dataLength, uint256 gasLimit, uint256 numberOfTokens) internal view {
//         // Check that payload is formed correctly
//         uint256 maxDataBytes = uint256(s_dynamicConfig.maxDataBytes);
//         if (dataLength > maxDataBytes) revert MessageTooLarge(maxDataBytes, dataLength);
//         if (gasLimit > uint256(s_dynamicConfig.maxPerMsgGasLimit)) revert MessageGasLimitTooHigh();
//         if (numberOfTokens > uint256(s_dynamicConfig.maxNumberOfTokensPerMsg)) revert UnsupportedNumberOfTokens();
//     }

//     /// @notice Returns the token transfer cost parameters.
//     /// A basis point fee is calculated from the USD value of each token transfer.
//     /// For each individual transfer, this fee is between [minFeeUSD, maxFeeUSD].
//     /// Total transfer fee is the sum of each individual token transfer fee.
//     /// @dev Assumes that tokenAmounts are validated to be listed tokens elsewhere.
//     /// @dev Splitting one token transfer into multiple transfers is discouraged,
//     /// as it will result in a transferFee equal or greater than the same amount aggregated/de-duped.
//     /// @param feeToken address of the feeToken.
//     /// @param feeTokenPrice price of feeToken in USD with 18 decimals.
//     /// @param tokenAmounts token transfers in the message.
//     /// @return tokenTransferFeeUSDWei total token transfer bps fee in USD with 18 decimals.
//     /// @return tokenTransferGas total execution gas of the token transfers.
//     /// @return tokenTransferBytesOverhead additional token transfer data passed to destination, e.g. USDC attestation.
//     function _getTokenTransferCost(
//         address feeToken,
//         uint224 feeTokenPrice,
//         Client.EVMTokenAmount[] calldata tokenAmounts
//     )
//         internal
//         view
//         returns (uint256 tokenTransferFeeUSDWei, uint32 tokenTransferGas, uint32 tokenTransferBytesOverhead)
//     {
//         uint256 numberOfTokens = tokenAmounts.length;

//         for (uint256 i = 0; i < numberOfTokens; ++i) {
//             Client.EVMTokenAmount memory tokenAmount = tokenAmounts[i];
//             TokenTransferFeeConfig memory transferFeeConfig = s_tokenTransferFeeConfig[tokenAmount.token];

//             // Validate if the token is supported, do not calculate fee for unsupported tokens.
//             // if (!s_poolsBySourceToken.contains(tokenAmount.token)) revert UnsupportedToken(IERC20(tokenAmount.token));

//             uint256 bpsFeeUSDWei = 0;
//             // Only calculate bps fee if ratio is greater than 0. Ratio of 0 means no bps fee for a token.
//             // Useful for when the PriceRegistry cannot return a valid price for the token.
//             if (transferFeeConfig.deciBps > 0) {
//                 uint224 tokenPrice = 0;
//                 if (tokenAmount.token != feeToken) {
//                     tokenPrice = IPriceRegistry(s_dynamicConfig.priceRegistry).getValidatedTokenPrice(tokenAmount.token);
//                 } else {
//                     tokenPrice = feeTokenPrice;
//                 }

//                 // Calculate token transfer value, then apply fee ratio
//                 // ratio represents multiples of 0.1bps, or 1e-5
//                 bpsFeeUSDWei =
//                     (tokenPrice._calcUSDValueFromTokenAmount(tokenAmount.amount) * transferFeeConfig.deciBps) / 1e5;
//             }

//             tokenTransferGas += transferFeeConfig.destGasOverhead;
//             tokenTransferBytesOverhead += transferFeeConfig.destBytesOverhead;

//             // Bps fees should be kept within range of [minFeeUSD, maxFeeUSD].
//             // Convert USD values with 2 decimals to 18 decimals.
//             uint256 minFeeUSDWei = uint256(transferFeeConfig.minFeeUSDCents) * 1e16;
//             if (bpsFeeUSDWei < minFeeUSDWei) {
//                 tokenTransferFeeUSDWei += minFeeUSDWei;
//                 continue;
//             }

//             uint256 maxFeeUSDWei = uint256(transferFeeConfig.maxFeeUSDCents) * 1e16;
//             if (bpsFeeUSDWei > maxFeeUSDWei) {
//                 tokenTransferFeeUSDWei += maxFeeUSDWei;
//                 continue;
//             }

//             tokenTransferFeeUSDWei += bpsFeeUSDWei;
//         }

//         return (tokenTransferFeeUSDWei, tokenTransferGas, tokenTransferBytesOverhead);
//     }

//     /// @notice Returns the estimated data availability cost of the message.
//     /// @dev To save on gas, we use a single destGasPerDataAvailabilityByte value for both zero and non-zero bytes.
//     /// @param dataAvailabilityGasPrice USD per data availability gas in 18 decimals.
//     /// @param messageDataLength length of the data field in the message.
//     /// @param numberOfTokens number of distinct token transfers in the message.
//     /// @param tokenTransferBytesOverhead additional token transfer data passed to destination, e.g. USDC attestation.
//     /// @return dataAvailabilityCostUSD36Decimal total data availability cost in USD with 36 decimals.
//     function _getDataAvailabilityCost(
//         uint112 dataAvailabilityGasPrice,
//         uint256 messageDataLength,
//         uint256 numberOfTokens,
//         uint32 tokenTransferBytesOverhead
//     ) internal view returns (uint256 dataAvailabilityCostUSD36Decimal) {
//         uint256 dataAvailabilityLengthBytes = Internal.MESSAGE_FIXED_BYTES + messageDataLength
//             + (numberOfTokens * Internal.MESSAGE_FIXED_BYTES_PER_TOKEN) + tokenTransferBytesOverhead;

//         // destDataAvailabilityOverheadGas is a separate config value for flexibility to be updated independently of message cost.
//         uint256 dataAvailabilityGas = (dataAvailabilityLengthBytes * s_dynamicConfig.destGasPerDataAvailabilityByte)
//             + s_dynamicConfig.destDataAvailabilityOverheadGas;

//         // dataAvailabilityGasPrice is in 18 decimals, destDataAvailabilityMultiplierBps is in 4 decimals
//         // we pad 14 decimals to bring the result to 36 decimals, in line with token bps and execution fee.
//         return ((dataAvailabilityGas * dataAvailabilityGasPrice) * s_dynamicConfig.destDataAvailabilityMultiplierBps)
//             * 1e14;
//     }
// }
