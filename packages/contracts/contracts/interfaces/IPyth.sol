// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPyth {
    function getUpdateFee(
        bytes[] calldata updateData
    ) external view returns (uint256);

    function updatePriceFeeds(bytes[] calldata updateData) external payable;

    function getPriceNoOlderThan(
        bytes32 id,
        uint age
    )
        external
        view
        returns (int64 price, uint64 conf, int32 expo, uint publishTime);
}
