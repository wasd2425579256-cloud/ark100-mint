// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice 2.5% market fee. Rounding dust stays with the seller (fee rounds down).
library MarketFee {
    uint256 internal constant BPS = 250;

    function split(uint256 amount) internal pure returns (uint256 fee, uint256 proceeds) {
        fee = (amount * BPS) / 10_000;
        proceeds = amount - fee;
    }
}
