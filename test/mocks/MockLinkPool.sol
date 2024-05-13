// SDPX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IPool} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/pools/IPool.sol";
import {IERC20} from
    "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/contracts/token/ERC20/IERC20.sol";

contract MockLinkPool is IPool {
    IERC20 private linkToken;

    constructor(address _linkToken) {
        linkToken = IERC20(_linkToken);
    }

    function setLinkToken(IERC20 _linkToken) external {
        linkToken = _linkToken;
    }

    /// @notice Lock tokens into the pool or burn the tokens.
    /// @param originalSender Original sender of the tokens.
    /// @param receiver Receiver of the tokens on destination chain.
    /// @param amount Amount to lock or burn.
    /// @param destChainSelector Destination chain Id.
    /// @param extraArgs Additional data passed in by sender for lockOrBurn processing
    /// in custom pools on source chain.
    /// @return retData Optional field that contains bytes. Unused for now but already
    /// implemented to allow future upgrades while preserving the interface.
    function lockOrBurn(
        address originalSender,
        bytes calldata receiver,
        uint256 amount,
        uint64 destChainSelector,
        bytes calldata extraArgs
    ) external returns (bytes memory) {}

    /// @notice Releases or mints tokens to the receiver address.
    /// @param originalSender Original sender of the tokens.
    /// @param receiver Receiver of the tokens.
    /// @param amount Amount to release or mint.
    /// @param sourceChainSelector Source chain Id.
    /// @param extraData Additional data supplied offchain for releaseOrMint processing in
    /// custom pools on dest chain. This could be an attestation that was retrieved through a
    /// third party API.
    /// @dev offchainData can come from any untrusted source.
    function releaseOrMint(
        bytes memory originalSender,
        address receiver,
        uint256 amount,
        uint64 sourceChainSelector,
        bytes memory extraData
    ) external {}

    /// @notice Gets the IERC20 token that this pool can lock or burn.
    /// @return token The IERC20 token representation.
    function getToken() external view returns (IERC20 token) {
        return linkToken;
    }
}
