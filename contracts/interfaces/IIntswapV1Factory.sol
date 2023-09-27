// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IIntswapV1Factory {
    function addRoyalty(uint256 _amount) external;
    function hook(bytes32 action, bytes memory data) external;
    function getProtocolFeeInfo() external view returns (address, uint256);
    function getFeeRatio() external view returns (uint256);
    function getRoyaltyInfo(address pair) external view returns (address, uint256);
    function getPair(address nft) external view returns (address);
    function isOfficialPair(address pair) external view returns (bool);
    function isAllowedToCall(address called, address caller, bytes32 action) external view returns(bool);
}