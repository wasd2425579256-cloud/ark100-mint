// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PancakeZap} from "../PancakeZap.sol";
import {MockWETH} from "./MockWETH.sol";

interface IERC20Mini {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

/// @notice Pair + LP token. Reserves track token balances except when a test calls `skew`.
contract MockLP {
    address public immutable token0;
    address public immutable token1;
    address public immutable router;

    uint112 private _r0;
    uint112 private _r1;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(address a, address b, address router_) {
        (token0, token1) = a < b ? (a, b) : (b, a);
        router = router_;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (_r0, _r1, uint32(block.timestamp));
    }

    function mint(address to) external returns (uint256 liquidity) {
        uint256 b0 = IERC20Mini(token0).balanceOf(address(this));
        uint256 b1 = IERC20Mini(token1).balanceOf(address(this));
        uint256 amount0 = b0 - uint256(_r0);
        uint256 amount1 = b1 - uint256(_r1);
        if (totalSupply == 0) {
            liquidity = _sqrt(amount0 * amount1);
        } else {
            liquidity = _min((amount0 * totalSupply) / _r0, (amount1 * totalSupply) / _r1);
        }
        require(liquidity > 0, "liq");
        totalSupply += liquidity;
        balanceOf[to] += liquidity;
        _r0 = _to112(b0);
        _r1 = _to112(b1);
    }

    /// @dev Router-only. Sends `token` out, then syncs reserves to balances (input token already delivered).
    function deliver(address token, uint256 amount, address to) external {
        require(msg.sender == router, "router");
        require(IERC20Mini(token).transfer(to, amount), "xfer");
        _r0 = _to112(IERC20Mini(token0).balanceOf(address(this)));
        _r1 = _to112(IERC20Mini(token1).balanceOf(address(this)));
    }

    /// @dev Moves the price the sale reads without transferring tokens. Used to prove the slippage check
    ///      refuses to zap. Do not swap afterwards: output is sized off these reserves.
    function skew(address wbnb, uint256 bnbReserve, uint256 arkReserve) external {
        if (token0 == wbnb) {
            _r0 = _to112(bnbReserve);
            _r1 = _to112(arkReserve);
        } else {
            _r1 = _to112(bnbReserve);
            _r0 = _to112(arkReserve);
        }
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
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

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function skim(address to) external {
        uint256 e0 = IERC20Mini(token0).balanceOf(address(this)) - uint256(_r0);
        uint256 e1 = IERC20Mini(token1).balanceOf(address(this)) - uint256(_r1);
        if (e0 > 0) require(IERC20Mini(token0).transfer(to, e0), "skim0");
        if (e1 > 0) require(IERC20Mini(token1).transfer(to, e1), "skim1");
    }

    function sync() external {
        _r0 = _to112(IERC20Mini(token0).balanceOf(address(this)));
        _r1 = _to112(IERC20Mini(token1).balanceOf(address(this)));
    }

    function _to112(uint256 v) internal pure returns (uint112) {
        require(v <= type(uint112).max, "112");
        return uint112(v);
    }
}

contract MockFactory {
    address public immutable router;
    mapping(address => mapping(address => address)) public getPair;
    address public lastPair;

    constructor(address router_) {
        router = router_;
    }

    function createPair(address a, address b) external returns (address pair) {
        require(a != b && a != address(0) && b != address(0), "addr");
        require(getPair[a][b] == address(0), "exists");
        pair = address(new MockLP(a, b, router));
        getPair[a][b] = pair;
        getPair[b][a] = pair;
        lastPair = pair;
    }
}

/// @notice PancakeRouter stand-in: 0.25% swaps and the same add-liquidity quote as V2.
contract MockRouter {
    MockWETH public immutable wbnb;
    MockFactory public immutable factory_;

    constructor(MockWETH wbnb_) {
        wbnb = wbnb_;
        factory_ = new MockFactory(address(this));
    }

    function WETH() external view returns (address) {
        return address(wbnb);
    }

    function factory() external view returns (address) {
        return address(factory_);
    }

    function lp() external view returns (MockLP) {
        return MockLP(factory_.lastPair());
    }

    function skew(uint256 bnbReserve, uint256 arkReserve) external {
        MockLP(factory_.lastPair()).skew(address(wbnb), bnbReserve, arkReserve);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        require(block.timestamp <= deadline, "expired");
        address pair = factory_.getPair(token, address(wbnb));
        require(pair != address(0), "pair");
        (amountToken, amountETH) = _quoteAdd(pair, amountTokenDesired, amountTokenMin, amountETHMin);
        require(IERC20Mini(token).transferFrom(msg.sender, pair, amountToken), "pull");
        wbnb.deposit{value: amountETH}();
        require(wbnb.transfer(pair, amountETH), "wbnb");
        liquidity = MockLP(pair).mint(to);
        if (msg.value > amountETH) {
            (bool sent,) = msg.sender.call{value: msg.value - amountETH}("");
            require(sent, "refund");
        }
    }

    function _quoteAdd(address pair, uint256 amountTokenDesired, uint256 amountTokenMin, uint256 amountETHMin)
        internal
        view
        returns (uint256 amountToken, uint256 amountETH)
    {
        MockLP p = MockLP(pair);
        (uint112 r0, uint112 r1,) = p.getReserves();
        uint256 reserveToken;
        uint256 reserveEth;
        if (p.token0() == address(wbnb)) {
            reserveEth = uint256(r0);
            reserveToken = uint256(r1);
        } else {
            reserveToken = uint256(r0);
            reserveEth = uint256(r1);
        }
        if (reserveEth == 0 && reserveToken == 0) {
            amountToken = amountTokenDesired;
            amountETH = msg.value;
        } else if ((amountTokenDesired * reserveEth) / reserveToken <= msg.value) {
            amountETH = (amountTokenDesired * reserveEth) / reserveToken;
            require(amountETH >= amountETHMin, "INSUFFICIENT_B_AMOUNT");
            amountToken = amountTokenDesired;
        } else {
            amountToken = (msg.value * reserveToken) / reserveEth;
            require(amountToken >= amountTokenMin, "INSUFFICIENT_A_AMOUNT");
            amountETH = msg.value;
        }
        require(amountToken >= amountTokenMin && amountETH >= amountETHMin, "min");
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts)
    {
        require(block.timestamp <= deadline, "expired");
        require(path.length == 2 && path[0] == address(wbnb) && msg.value > 0, "path");
        address pair = factory_.getPair(path[1], address(wbnb));
        require(pair != address(0), "pair");
        MockLP p = MockLP(pair);
        (uint112 r0, uint112 r1,) = p.getReserves();
        (uint256 reserveToken, uint256 reserveEth) =
            p.token0() == address(wbnb) ? (uint256(r1), uint256(r0)) : (uint256(r0), uint256(r1));
        uint256 amountOut = PancakeZap.amountOut(msg.value, reserveEth, reserveToken);
        require(amountOut >= amountOutMin && amountOut > 0, "out");
        wbnb.deposit{value: msg.value}();
        require(wbnb.transfer(pair, msg.value), "wbnb");
        p.deliver(path[1], amountOut, to);
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = amountOut;
    }
}
