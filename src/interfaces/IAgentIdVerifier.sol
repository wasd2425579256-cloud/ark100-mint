// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IAgentIdVerifier {
    function verify(address account) external view returns (bool ok, string memory handle);
}
