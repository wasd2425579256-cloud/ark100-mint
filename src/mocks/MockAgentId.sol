// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Test double for the Agent ID gate. `verify` is true only when allowed and a handle is set.
contract MockAgentId {
    mapping(address => bool) public allowed;
    mapping(address => string) public handleOf;

    function setAllowed(address account, bool ok, string calldata handle) external {
        allowed[account] = ok;
        handleOf[account] = handle;
    }

    function verify(address account) external view returns (bool ok, string memory handle) {
        handle = handleOf[account];
        ok = allowed[account] && bytes(handle).length > 0;
    }
}
