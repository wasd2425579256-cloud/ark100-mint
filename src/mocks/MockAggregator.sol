// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice 8-decimal Chainlink stand-in. `updatedAt == 0` means "as of this block", so warps stay fresh
///         until a test pins a timestamp with `setUpdatedAt`.
contract MockAggregator {
    int256 public answer;
    uint8 public decimals = 8;
    uint256 public updatedAt;

    constructor(int256 answer_) {
        answer = answer_;
    }

    function setAnswer(int256 answer_) external {
        answer = answer_;
    }

    function setUpdatedAt(uint256 ts) external {
        updatedAt = ts;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        uint256 ts = updatedAt == 0 ? block.timestamp : updatedAt;
        return (1, answer, ts, ts, 1);
    }
}
