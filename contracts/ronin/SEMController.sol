// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "../lib/Pausable.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "../../interfaces/IRoninGateway.sol";

abstract contract SEMController is Pausable {

	error ErrInvalidOperator();
	error ErrInvalidBridgeOperator();
	error ErrOperatorHasAlreadyVoted();
	error ErrTooMuchEtherRequested();
	error ErrNothingToSend();

	uint256 constant _ETH_CHAIN_ID = 1;

	address public gateway;
	address public semOnETH;
	uint256 public totalValueOnETH;

	uint256 public withdrawalEpoch;
	uint256 public weightNeeded;

	mapping(address => bool) public operator;

	event StakingCommandQueried(uint256 amount);
	event UnstakingCommandQueried(uint256 amount);

	constructor(address _gateway, address _semOnETH) {
		gateway = _gateway;
		semOnETH = _semOnETH;
	}

	modifier onlyOperator() {
		if (msg.sender != owner() || operator[msg.sender]) revert ErrInvalidOperator();
		_;
	}

	function asset() public view virtual returns (address);

	/**
	 * @notice
	 * Owner gated function to add or remove an operator
	 * @param _operator Address of the operator
	 * @param _value Boolean value to add or remove the operator
	 */
	function updateOperator(address _operator, bool _value) external onlyOwner {
		operator[_operator] = _value;
	}

	/**
	 * @notice
	 * Owner gated function to update the weight needed for a successful vote
	 * @param _value New weight needed
	 */
	function updateWeight(uint256 _value) external onlyOwner {
		weightNeeded = _value;
	}

	/**
	 * @notice
	 * External function that gives the amount of ether available for staking
	 * @return Amount of ether available for staking	 
	 */
	function bufferSize() public view returns (uint256) {
		return IERC20(asset()).balanceOf(address(this));
	}

	/**
	 * @notice
	 * External function that allows the operator to send a staking command to the contract
	 * @param _amount Amount of ether to be staked
	 */
	function _sendStakingCommand(uint256 _amount) internal {
		if (_amount > bufferSize()) revert ErrTooMuchEtherRequested();
		if (_amount == 0) revert ErrNothingToSend();

		IRoninGateway.Request memory request = IRoninGateway.Request({
			recipientAddr: semOnETH,
			tokenAddr: asset(),
			info: IRoninGateway.Info({
				erc: IRoninGateway.Standard.ERC20,
				id: 0,
				quantity: _amount
			})
		});
		IRoninGateway(gateway).requestWithdrawalFor(request, _ETH_CHAIN_ID);
		emit StakingCommandQueried(_amount);
	}

	/**
	 * @notice
	 * External function that allows the operator to send an unstaking command to the contract
	 * @param _amount Amount of ether to be unstaked
	 */
	function _sendUnstakingCommand(uint256 _amount) internal {
		if (_amount > totalValueOnETH) revert ErrTooMuchEtherRequested();
		if (_amount == 0) revert ErrNothingToSend();

		emit UnstakingCommandQueried(_amount);
	}
}