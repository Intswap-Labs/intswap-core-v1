// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IIntswapV1Permision {
    function isAllowedToCall(address called, address caller, bytes32 action) external view returns(bool);
}