// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "../lib/Pausable.sol";
import "./RocketPoolStakeManager.sol";
import "./RoninBridgeManager.sol";
import "./StakeWiseManager.sol";

error ErrInvalidSEMOperator();
error ErrNoNeedToUnstake();
error ErrCannotStake();
error ErrExit();

enum SEMStatus {
	ONLINE,
	SHUTDOWN
}

contract StakedEtherManager is
		 StakeWiseManager,
		 RocketPoolStakeManager,
		 RoninBridgeManager,
		 Pausable {

	SEMStatus public semState;
	mapping(address => bool) public semOperator;

	constructor(
		address _swVault,
		address _reth,
		address _pool,
		address _bridge)
		StakeWiseManager(_swVault)
		RocketPoolStakeManager(_reth, _pool)
		RoninBridgeManager(_bridge) {
	}

	modifier onlySEMOperator() {
		if (msg.sender != owner() || semOperator[msg.sender]) revert ErrInvalidSEMOperator();
		_;
	}

	function updateOperator(address _operator, bool _value) external onlyOwner {
		semOperator[_operator] = _value;
	}

	function overrideState(SEMStatus _state) external onlyOwner {
		semState = _state;
	}

	/**  
	 * @notice
	 * External function that allows the SEM contract to be exited graciously. RETH is converted back into ether and withdrawal
	 * requests are submitted to StakeWise. Remaining ether is sent to the bridge.
	 */
	function exitInit() external onlyOwner {
		if (semState != SEMStatus.SHUTDOWN) revert ErrExit();

		_exitFromRocketPool();
		_paybackBridge(address(this).balance);
		_withdrawInitQueueStakeWise(type(uint256).max);
	}

	/**  
	 * @notice
	 * External function that allows the SEM contract to finalise exiting on StakeWise and send the remaining ether to the bridge
	 * @param _ticket Ticket ID of the withdrawal request
	 * @param _timestamp Timestamp of the withdrawal request
	 * @param _queueIndex Index of the withdrawal request in the queue
	 */
	function exitFinalise(uint256 _ticket, uint256 _timestamp, uint256 _queueIndex) external onlyOwner {
		if (semState != SEMStatus.SHUTDOWN) revert ErrExit();

		_withdrawExitQueueStakeWise(_ticket, _timestamp, _queueIndex);
		_paybackBridge(address(this).balance);
	}

	/**  
	 * @notice
	 * Public function to calculate the amount of ether held by the SEM from LSD shares
	 * @return Total amount of ether held by the SEM
	 */
	function totalStake() public view returns(uint256) {
		return IRETH(RETH).getEthValue(IRETH(RETH).balanceOf(address(this))) + _totalStaked();
	}

	/**  
	 * @notice
	 * External function that allows to deposit ether into LSDs
	 * @param _ratios Ratio provided to specify how much ether to deposit in each LSD (RP, lido, frax)
	 * @param _receipt Receipt of the request
	 * @param _signatures Signatures of the request
	 */
	function stake(uint256[2] calldata _ratios, IRoninGateway.Receipt calldata _receipt, IRoninGateway.Signature[] calldata _signatures) external onlySEMOperator whenNotPaused {
		if (semState != SEMStatus.ONLINE) revert ErrCannotStake();

		_requestEtherFromBridge(_receipt, _signatures);
		_stakeInRocketPool(_ratios[0]);
		_stakeInStakeWise(_ratios[1]);
	}

	/**  
	 * @notice
	 * External function that to withdraw ether from LSDs after a withdrawal request has been submitted. It will withdraw from Rocketpool
	 * and initiate withdrawal of lido and frax that will generate NFTs to be claimed later
	 * @param _ratios Ratio provided to specify how much ether to withdraw from each LSD (RP, lido, frax)
	 */
	function unstakeInstant(uint256[2] calldata _ratios) external onlySEMOperator whenNotPaused {
		if (semState != SEMStatus.ONLINE) revert ErrNoNeedToUnstake();

		_withdrawExactEthFromRocketPool(_ratios[0]);
		_withdrawExactEthFromStakeWise(_ratios[1]);
	}

	/**  
	 * @notice
	 * External function that allows the operator to send an unstaking command to the SW vault
	 * @param _amount Amount of ether to be unstaked
	 */
	function unstakeQueue(uint256 _amount) external onlySEMOperator whenNotPaused {
		if (semState != SEMStatus.ONLINE) revert ErrNoNeedToUnstake();

		_withdrawInitQueueStakeWise(_amount);
	}

	/**  
	 * @notice
	 * External function that finalises an unstaking command on SW vault
	 * @param _ticket Ticket ID of the withdrawal request
	 * @param _timestamp Timestamp of the withdrawal request
	 * @param _queueIndex Index of the withdrawal request in the queue
	 */
	function unstakeQueueFinalise(uint256 _ticket, uint256 _timestamp, uint256 _queueIndex) external onlySEMOperator whenNotPaused {
		_withdrawExitQueueStakeWise(_ticket, _timestamp, _queueIndex);
	}

	receive() external payable {}
}