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
import "./LidoStakeManager.sol";
import "./FraxStakeManager.sol";
import "./RoninBridgeManager.sol";
import "./QuorumManager.sol";

error ErrLatestBalanceCannotBeSmaller();
error ErrNothingToStake();
error ErrSEMAlreadyInWithdrawalCycle();
error ErrInvalidSEMOperator();
error ErrTooMuchEtherRequested();
error ErrSum();
error ErrNoNeedToUnstake();
error ErrCannotStake();
error ErrExit();


enum SEMStatus {
	STANDBY,
	INITIATED,
	SHUTDOWN
}

contract StakedEtherManager is
		 RocketPoolStakeManager,
		 LidoStakeManager,
		 RoninBridgeManager,
		 FraxStakeManager,
		 QuorumManager,
		 Pausable {
	uint256 constant public MAX_PRECISION = 10_000;
	// keccak256("cumulativeWETHStaked")
	bytes32 constant public CUMULATIVE_HASH = 0x71a4612cb38a450aa2e0d0adf2336a60552e49a7344e54432ee30e6bd4066ec3;

	// keccak256("ETHToWithdrawPerEpoch")
	bytes32 constant public ETH_REQUIRED_HASH = 0xd285e754ead803ece6d8c29f3a41293518a1874a4b27f5551ba4e6bc9be0a1b6;


	uint256 public cumulativeWethStakedCheckpoint;
	uint256 public cumulativeWETHStaked;

	uint256 lastLoggedTotalStake;
	uint256 public withdrawalEpoch;
	SEMStatus public SEMState;
	uint256 public currentEpoch;

	mapping(uint256 => uint256) public ETHToWithdrawPerEpoch;
	mapping(uint256 => uint256) public ETHWithdrawnPerEpoch;
	mapping(address => bool) public SEMOperator;

	// this event should mint WETH into splitter contract on ronin
	event RealiseRewards(uint256 rewardAmount);

	constructor(
		address _wsteth,
		address _lidoQueue,
		address _fraxMinter,
		address _fraxQueue,
		address _sfrxEth,
		address _reth,
		address _pool,
		address _bridge)
		RocketPoolStakeManager(_reth, _pool)
		LidoStakeManager(_wsteth, _lidoQueue) 
		FraxStakeManager(_fraxMinter, _fraxQueue, _sfrxEth)
		RoninBridgeManager(_bridge) {
	}

	modifier onlySEMOperator() {
		if (msg.sender != owner() || SEMOperator[msg.sender]) revert ErrInvalidSEMOperator();
		_;
	}

	function updateOperator(address _operator, bool _value) external onlyOwner {
		SEMOperator[_operator] = _value;
	}

	function overrideState(SEMStatus _state) external onlyOwner {
		SEMState = _state;
	}

	/**  
	 * @notice
	 * External function that allows the SEM contract to be exited graciously. RETH is converted back into ether and withdrawal
	 * NFTs are being created on lido and frax
	 */
	function exitInit() external onlyOwner {
		if (SEMState != SEMStatus.SHUTDOWN) revert ErrExit();

		_exitFromRocketPool();
		_initiateExitFromLido();
		_initiateExitFromFrax();
		_paybackBridge(address(this).balance);
	}

	/**  
	 * @notice
	 * External function that allows the SEM contract to finalise exiting on lido and frax by burning the withdrawal NFTs into ether
	 * @param _lidoIndex Index of the lido withdrawal on the SEM
	 * @param _fraxIndex Index of the frax withdrawal on the SEM
	 */
	function exitFinalise(uint256 _lidoIndex, uint256 _fraxIndex) external onlyOwner {
		if (SEMState != SEMStatus.SHUTDOWN) revert ErrExit();

		_finaliseExitFromLido(_lidoIndex);
		_finaliseExitFromFrax(_fraxIndex);
		_paybackBridge(address(this).balance);
	}

	/**  
	 * @notice
	 * Public function to calculate the amount of ether held by the SEM from LSD shares
	 */
	function totalStake() public view returns(uint256) {
		return IRETH(RETH).getEthValue(IRETH(RETH).balanceOf(address(this))) +
			   IwstETH(wstETH).getStETHByWstETH(IwstETH(wstETH).balanceOf(address(this))) + 
			   ISfrxEth(SFRXETH).convertToAssets(ISfrxEth(SFRXETH).balanceOf(address(this)));
	}

	/**  
	 * @notice
	 * External function that updates the cumulativeWETHStaked variable. This allows to calculate how much ether has been staked on 
	 * the ronin strETH contract
	 * @param _cumulativeWETHStaked Current amount of cumlated WETH staked on ronin
	 * @param _signatures signatures provided by bridge operators to enable this function to be executed.
	 * 					  If quorum if signatures is not reached, this functino will revert.
	 */
	function consensusUpdateCumulative(uint256 _cumulativeWETHStaked, Signature[] calldata _signatures) external whenNotPaused {
		if (_cumulativeWETHStaked < cumulativeWETHStaked) revert ErrLatestBalanceCannotBeSmaller();

		_validateSignatures(_cumulativeWETHStaked, CUMULATIVE_HASH, _getBridgeManager(), _signatures);
		cumulativeWETHStaked = _cumulativeWETHStaked;
	}

	/**  
	 * @notice
	 * External function that sets the SEM contract into the initiated state allowing for the withdrawal of ether from LSDs
	 * @param _ethToBeWithdrawn Amount of ether required to be sent back to the ronin bridge
	 * @param _signatures signatures provided by bridge operators to enable this function to be executed.
	 * 					  If quorum if signatures is not reached, this functino will revert.
	 */
	function consensusInitiateWithdrawalRequest(uint256 _ethToBeWithdrawn, Signature[] calldata _signatures) external whenNotPaused {
		if (SEMState != SEMStatus.STANDBY) revert ErrSEMAlreadyInWithdrawalCycle();

		_validateSignatures(_ethToBeWithdrawn, ETH_REQUIRED_HASH, _getBridgeManager(), _signatures);
		SEMState = SEMStatus.INITIATED;
		ETHToWithdrawPerEpoch[currentEpoch] = _ethToBeWithdrawn;
	}

	/**  
	 * @notice
	 * External function that allows to deposit ether into LSDs
	 * @param _ratios Ratio provided to specify how much ether to deposit in each LSD (RP, lido, frax)
	 * @param _desiredAmount Total amount of ether to be deposited. Must be lower or equal than current available ether to be deposited
	 */
	function stake(uint256[3] calldata _ratios, uint256 _desiredAmount) external onlySEMOperator whenNotPaused {
		uint256 amount = cumulativeWETHStaked - cumulativeWethStakedCheckpoint;
		if (SEMState != SEMStatus.STANDBY) revert ErrCannotStake();
		if (amount == 0) revert ErrNothingToStake();
		if (_desiredAmount > amount) revert ErrTooMuchEtherRequested();
		if (_ratios[0] + _ratios[1] + _ratios[2] != MAX_PRECISION) revert ErrSum();

		cumulativeWethStakedCheckpoint += _desiredAmount;
		_realiseRewards();
		_requestEtherFromBridge(_desiredAmount);
		_stakeInRocketPool(_desiredAmount * _ratios[0] / MAX_PRECISION);
		_stakeInLido(_desiredAmount * _ratios[1] / MAX_PRECISION);
		_stakeInFrax(_desiredAmount * _ratios[2] / MAX_PRECISION);
		lastLoggedTotalStake = totalStake();
	}

	/**  
	 * @notice
	 * External function that allows to deposit ether dust into LSDs
	 * @param _ratios Ratio provided to specify how much ether to deposit in each LSD (RP, lido, frax)
	 */
	function stakeDust(uint256[3] calldata _ratios) external onlySEMOperator whenNotPaused {
		uint256 _desiredAmount = address(this).balance;
		if (SEMState != SEMStatus.STANDBY) revert ErrCannotStake();
		if (_desiredAmount == 0) revert ErrNothingToStake();
		if (_ratios[0] + _ratios[1] + _ratios[2] != MAX_PRECISION) revert ErrSum();

		_realiseRewards();
		_stakeInRocketPool(_desiredAmount * _ratios[0] / MAX_PRECISION);
		_stakeInLido(_desiredAmount * _ratios[1] / MAX_PRECISION);
		_stakeInFrax(_desiredAmount * _ratios[2] / MAX_PRECISION);
		lastLoggedTotalStake = totalStake();
	}

	/**  
	 * @notice
	 * External function that to withdraw ether from LSDs after a withdrawal request has been submitted. It will withdraw from Rocketpool
	 * and initiate withdrawal of lido and frax that will generate NFTs to be claimed later
	 * @param _ratios Ratio provided to specify how much ether to withdraw from each LSD (RP, lido, frax)
	 * @param _desiredAmount Total amount of ether to be withdrawn during this call (not necessarily equal to asked amount by bridge)
	 */
	function unstakeInit(uint256[3] calldata _ratios, uint256 _desiredAmount) external onlySEMOperator whenNotPaused {
		uint256 amountToBeWithdrawn;
		uint256 currentWithdrawn = ETHWithdrawnPerEpoch[currentEpoch];
		uint256 totalNeeded = ETHToWithdrawPerEpoch[currentEpoch];
		uint256 unstakedAmount;
		if (_ratios[0] + _ratios[1] + _ratios[2] != MAX_PRECISION) revert ErrSum();
		if (SEMState != SEMStatus.INITIATED) revert ErrNoNeedToUnstake();

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

	/**  
	 * @notice
	 * External function that to withdraw ether from LSDs after a withdrawal request has been submitted. It will withdraw from Lido and frax
	 * by burning previously minted NFTs.
	 */
	function unstakeFinalise() external onlySEMOperator whenNotPaused {
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

	/**  
	 * @notice
	 * Internal function that is called during a withdrawal request. It checks if the current max deposit ether amount can fill the withdrawal request.
	 * If it can fill fully or partially, it consumes the deposit amount and prepares to send it back to bridge.
	 * @param _needed Ether amount needed to fulfill withdrawal request amount
	 */
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

	/**  
	 * @notice
	 * Internal function that is called at the end withdrawal request. It is called with enough ether has been gathered from LSD withdawals
	 * or from consuming the deposit amount.
	 * @param _totalNeeded Total ether requested by the bridge to be sent back
	 */
	function _finaliseWithdrawalEpoch(uint256 _totalNeeded) internal {
		currentEpoch++;
		SEMState = SEMStatus.STANDBY;
		_paybackBridge(_totalNeeded);
	}

	/**  
	 * @notice
	 * Internal function that is called before any deposit or withdrawal actions.
	 * It logs the amount of realised ether rewards obtained since last check. Such event should trigger WETH minting on ronin
	 */
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