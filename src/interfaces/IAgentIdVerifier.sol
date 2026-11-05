// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Pluggable Agent ID gate. NestEgg-style registry on BSC:
/// 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F (balanceOf > 0 && handle non-empty).
interface IAgentIdVerifier {
    /// @return ok True if `account` may mint Gen0 tickets.
    /// @return handle Bound Agent handle (empty if none).
    function verify(address account) external view returns (bool ok, string memory handle);
}
