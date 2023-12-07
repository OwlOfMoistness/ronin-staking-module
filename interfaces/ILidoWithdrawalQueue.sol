// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

interface IWithdrawalQueue {
	function requestWithdrawalsWstETH(uint256[] calldata _amounts, address _owner) external returns (uint256[] memory requestIds);
	function findCheckpointHints(
		uint256[] calldata _requestIds,
		uint256 _firstIndex,
		uint256 _lastIndex) external view
        returns (uint256[] memory hintIds);
	function getLastCheckpointIndex() external view returns (uint256);
	function claimWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external;
}