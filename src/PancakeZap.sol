// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title PancakeZap — constant-product math for a one-sided BNB zap into a PancakeSwap V2 pair.
/// @dev Fee is 0.25% (9975/10000), matching PancakeRouter on BSC. The swap size is the positive
///      root of the quadratic that leaves the leftover BNB and the ARK bought in the post-swap
///      reserve ratio, so `addLiquidity` consumes both sides instead of refunding a growing remainder.
library PancakeZap {
    uint256 internal constant FEE_N = 9975;
    uint256 internal constant FEE_D = 10_000;

    /// @dev PancakeLibrary.getAmountOut.
    function amountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) return 0;
        uint256 amountInWithFee = amountIn * FEE_N;
        return (amountInWithFee * reserveOut) / (reserveIn * FEE_D + amountInWithFee);
    }

    /// @dev BNB to sell so a deposit of `bnbIn` (and no ARK) becomes balanced liquidity after the 0.25% fee.
    ///      Derivation: (b - s) / out = (x + s) / y', with out and y' the post-fee constant-product terms.
    ///      That reduces to n*s^2 + x*(n+d)*s - b*x*d = 0.
    function bnbToSwap(uint256 bnbIn, uint256 reserveBnb) internal pure returns (uint256) {
        if (bnbIn < 2 || reserveBnb == 0) return 0;
        uint256 x = reserveBnb;
        uint256 n = FEE_N;
        uint256 d = FEE_D;
        uint256 xnd = x * (n + d);
        uint256 under = xnd * xnd + (4 * n * d) * x * bnbIn;
        uint256 root = sqrt(under);
        if (root <= xnd) return 0;
        uint256 swapAmt = (root - xnd) / (2 * n);
        if (swapAmt == 0 || swapAmt >= bnbIn) return 0;
        return swapAmt;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
