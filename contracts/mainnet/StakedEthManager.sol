// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "@openzeppelin/access/Ownable.sol";
import "./RocketPoolStakeManager.sol";
import "./LidoStakeManager.sol";
import "./FraxStakeManager.sol";
import "./RoninBridgeManager.sol";

error ErrLatestBalanceCannotBeSmaller();
error ErrNothingToStake();
error ErrSEMAlreadyInWithdrawalCycle();
error ErrInvalidSEMOperator();
error ErrTooMuchEtherRequested();
error ErrSum();
error ErrNoNeedToUnstake();
error ErrCannotStake();


enum WithdrawalStatus {
	STANDBY,
	INITIATED
}

contract StakedEtherManager is RocketPoolStakeManager, LidoStakeManager, RoninBridgeManager, FraxStakeManager, Ownable {
	uint256 constant public MAX_PRECISION = 10_000;

	uint256 public cumulativeWethStakedCheckpoint;
	uint256 public cumulativeWETHStaked;

	uint256 lastLoggedTotalStake;
	uint256 public withdrawalEpoch;
	WithdrawalStatus public SEMState;
	uint256 public currentEpoch;

	mapping(uint256 => uint256) public ETHToWithdrawPerEpoch;
	mapping(uint256 => uint256) public ETHWithdrawnPerEpoch;
	mapping(address => bool) public operator;

	// this event should mint WETH into splitter contract on ronin
	event RealiseRewards(uint256 rewardAmount);

	constructor(
		address _wsteth,
		address _steth,
		address _lidoQueue,
		address _fraxMinter,
		address _fraxQueue,
		address _sfrxEth,
		address _reth,
		address _pool,
		address _bridge)
		RocketPoolStakeManager(_reth, _pool)
		LidoStakeManager(_wsteth, _steth, _lidoQueue) 
		FraxStakeManager(_fraxMinter, _fraxQueue, _sfrxEth)
		RoninBridgeManager(_bridge) {
	}

	modifier onlySEMOperator() {
		if (msg.sender != owner() || operator[msg.sender]) revert ErrInvalidSEMOperator();
		_;
	}

	function updateOperator(address _operator, bool _value) external onlyOwner {
		operator[_operator] = _value;
	}

	function totalStake() public view returns(uint256) {
		return IRETH(RETH).getEthValue(IRETH(RETH).balanceOf(address(this))) +
			   IwstETH(wstETH).getStETHByWstETH(IwstETH(wstETH).balanceOf(address(this)));
	}

	function consensusUpdateCumulative(uint256 _cumulativeWETHStaked, bytes[] calldata signatures) external {
		// TODO add consensus check where enough signatures are given to update the staking data appropriately
		if (_cumulativeWETHStaked < cumulativeWETHStaked) revert ErrLatestBalanceCannotBeSmaller();
		cumulativeWETHStaked = _cumulativeWETHStaked;
	}

	function consensusInitiateWithdrawalRequest(uint256 _ethToBeWithdrawn, bytes[] calldata signatures) external {
		// TODO add consensus check where enough signatures are given to update the staking data appropriately
		if (SEMState != WithdrawalStatus.STANDBY) revert ErrSEMAlreadyInWithdrawalCycle();
		SEMState = WithdrawalStatus.INITIATED;
		ETHToWithdrawPerEpoch[currentEpoch] = _ethToBeWithdrawn;
	}

	// Available amount should be computed off chain
	function stake(uint256[3] calldata _ratios, uint256 _desiredAmount) external onlySEMOperator {
		uint256 amount = cumulativeWETHStaked - cumulativeWethStakedCheckpoint;
		if (SEMState != WithdrawalStatus.STANDBY) revert ErrCannotStake();
		if (amount == 0) revert ErrNothingToStake();
		if (_desiredAmount > amount) revert ErrTooMuchEtherRequested();
		if (_ratios[0] + _ratios[1] + _ratios[2] != MAX_PRECISION) revert ErrSum();


		_realiseRewards();
		_requestEtherFromBridge(_desiredAmount);
		cumulativeWethStakedCheckpoint += _desiredAmount;
		_stakeInRocketPool(_desiredAmount * _ratios[0] / MAX_PRECISION);
		_stakeInLido(_desiredAmount * _ratios[1] / MAX_PRECISION);
		_stakeInFrax(_desiredAmount * _ratios[2] / MAX_PRECISION);
		lastLoggedTotalStake = totalStake();
	}

	function stakeDust(uint256[3] calldata _ratios) external onlySEMOperator {
		uint256 _desiredAmount = address(this).balance;
		if (SEMState != WithdrawalStatus.STANDBY) revert ErrCannotStake();
		if (_desiredAmount == 0) revert ErrNothingToStake();
		if (_ratios[0] + _ratios[1] + _ratios[2] != MAX_PRECISION) revert ErrSum();

		_realiseRewards();
		_stakeInRocketPool(_desiredAmount * _ratios[0] / MAX_PRECISION);
		_stakeInLido(_desiredAmount * _ratios[1] / MAX_PRECISION);
		_stakeInFrax(_desiredAmount * _ratios[2] / MAX_PRECISION);
		lastLoggedTotalStake = totalStake();
	}

	function unstakeInit(uint256[3] calldata _ratios, uint256 _desiredAmount) external onlySEMOperator {
		uint256 amountToBeWithdrawn;
		uint256 currentWithdrawn = ETHWithdrawnPerEpoch[currentEpoch];
		uint256 totalNeeded = ETHToWithdrawPerEpoch[currentEpoch];
		uint256 unstakedAmount;
		if (_ratios[0] + _ratios[1] + _ratios[2] != MAX_PRECISION) revert ErrSum();
		if (SEMState != WithdrawalStatus.INITIATED) revert ErrNoNeedToUnstake();

		_realiseRewards();
		unstakedAmount += _checkCumulativeWETHDepositForWithdrawal(totalNeeded - currentWithdrawn);
		if (currentWithdrawn + unstakedAmount >= totalNeeded) {
			_finaliseWithdrawalEpoch(totalNeeded);
		}
		else {
			_withdrawExactEthFromRocketPool(_desiredAmount * _ratios[0] / MAX_PRECISION);
			unstakedAmount += amountToBeWithdrawn;
			if (currentWithdrawn + unstakedAmount >= totalNeeded) {
				_finaliseWithdrawalEpoch(totalNeeded);
			}
			else {
				_initiateWithdrawExactEthFromLido(_desiredAmount * _ratios[1] / MAX_PRECISION);
				_initiateWithdrawExactEthFromFrax(_desiredAmount * _ratios[2] / MAX_PRECISION);
				if (unstakedAmount > 0)
					ETHWithdrawnPerEpoch[currentEpoch] += unstakedAmount;
			}
		}
		lastLoggedTotalStake = totalStake();
	}

	function unstakeFinalise() external onlySEMOperator {
		uint256 currentWithdrawn = ETHWithdrawnPerEpoch[currentEpoch];
		uint256 totalNeeded = ETHToWithdrawPerEpoch[currentEpoch];
		uint256 unstakedAmount;

		_realiseRewards();
		unstakedAmount += _finaliseWithdrawExactEthFromLido();
		unstakedAmount += _finaliseWithdrawExactEthFromFrax();
		if (currentWithdrawn + unstakedAmount >= totalNeeded)
			_finaliseWithdrawalEpoch(totalNeeded);
		else
			ETHWithdrawnPerEpoch[currentEpoch] += unstakedAmount;
		lastLoggedTotalStake = totalStake();
	}

	function _checkCumulativeWETHDepositForWithdrawal(uint256 _needed) internal returns(uint256){
		uint256 amountAvailable = cumulativeWETHStaked - cumulativeWethStakedCheckpoint;
		uint256 amountRequested = amountAvailable > _needed ? _needed : amountAvailable;

		if (amountAvailable > 0) {
			cumulativeWethStakedCheckpoint += amountRequested;
			_requestEtherFromBridge(amountRequested);
			return amountRequested;
		}
		return 0;
	}

	function _finaliseWithdrawalEpoch(uint256 _totalNeeded) internal {
		currentEpoch++;
		SEMState = WithdrawalStatus.STANDBY;
		_paybackBridge(_totalNeeded);
	}

	function _realiseRewards() internal {
		uint256 lastLog = lastLoggedTotalStake;
		uint256 currentTotalStaked = totalStake();

		if (lastLog == 0)
			lastLoggedTotalStake = currentTotalStaked;
		else
			emit RealiseRewards(currentTotalStaked - lastLog);
	}

	function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4) {
		return StakedEtherManager.onERC721Received.selector;
	}

	receive() external payable {}
}