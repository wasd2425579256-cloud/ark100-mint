// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal WBNB. `deposit` credits `msg.sender`; the pair reads `balanceOf`.
contract MockWETH {
    mapping(address => uint256) public balanceOf;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }
}
