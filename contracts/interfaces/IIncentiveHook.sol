// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IIncentiveHook {
    function hook(bytes32 action, bytes memory data) external;
}