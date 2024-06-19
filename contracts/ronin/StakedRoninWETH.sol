// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "@openzeppelin/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "../lib/Pausable.sol";
import "@openzeppelin/utils/math/Math.sol";
import "../../interfaces/IRoninGateway.sol";
import "../../interfaces/IBridgeManager.sol";
import "./SEMController.sol";
import "./Escrow.sol";

enum WithdrawalStatus {
	STANDBY,
	INITIATED,
	UNSTAKE_ACTION_BROADCASTED,
	FINALISED
}


// 1. Users can requestWithdrawal when state is STANDBY
// 2. Operator can initiateWithdrawal to change state to INITIATED
// 3. Operator can submitUnstakeAction to change state to UNSTAKE_ACTION_BROADCASTED.
//    This will allow to send back senough eth if necessary for users to redeem
// 4. Bridge Operators can submitTVLEpochVote to update the TVL on eth chain and change state to FINALISED.
// 	  Mainnet must push tvl log event
// 5. Users can redeem their strETH into WETH based on the price per share locked during step 4 via calculating 

contract StakedRoninWETH is ERC4626, SEMController {
	using Math for uint256;

	error ErrRequestFulfilled();
	error ErrWithdrawalProcessInitiated();
	error ErrWithdrawalProcessNotFinalised();
	error ErrWithdrawalEpochNotInitiated();
	error ErrWrongTVLSubmission();
	error ErrWithdrawalEpochAlreadyEngaged();

	struct WithdrawalRequest {
		bool fulfilled;
		uint256 shares;
	}

	struct LockedPricePerShare {
		uint256 shareSupply;
		uint256 assetSupply;
	}

	uint256 public depositLimit;
	address public escrow;

	mapping(uint256 => LockedPricePerShare) public 						lockedPricePerSharePerEpoch;
	mapping(uint256 => mapping(address => WithdrawalRequest)) public	withdrawalRequestsPerEpoch;
	mapping(uint256 => uint256) public 									lockedstrETHPerEpoch;
	mapping(uint256 => WithdrawalStatus) public							statusPerEpoch;
	mapping(uint256 => mapping(address => bool)) public 				votesPerEpoch;
	mapping(uint256 => uint256) public 									weightsPerEpoch;

	mapping(uint256 => uint256) public 									tvlPerEpoch;

	event WithdrawalRequested(address indexed requester, uint256 indexed epoch, uint256 amount);
	event WithdrawalCancelled(address indexed requester, uint256 indexed epoch, uint256 amount);
	event WithdrawalClaimed(address indexed claimer, uint256 indexed epoch, uint256 amount, uint256 pricePerShare);
	event WithdrawalProcessInitiated(uint256 indexed epoch, uint256 wethRequired);

	constructor(address _weth, address _gatewayV3)
		ERC4626(IERC20(_weth))
		ERC20("Staked Ronin Ether", "strETH")
		SEMController(_gatewayV3, _weth) {
		IERC20(_weth).approve(_gatewayV3, type(uint256).max);
		escrow = address(new Escrow(_weth));
	}

	function setDepositLimit(uint256 _limit) external onlyOwner {
		depositLimit = _limit;
	}

	function maxDeposit(address) public view virtual override returns (uint256) {
		uint256 shares = totalSupply();
		if (shares == 0) return depositLimit;
		uint256 assets = previewRedeem(shares); 
		return assets > depositLimit ? 0 : (depositLimit - assets);
	}

	function asset() public view override(ERC4626, SEMController) returns (address) {
		return ERC4626.asset();
	}

	function totalAssets() public view override returns (uint256) {
		return super.totalAssets() + totalValueOnETH;
	}

	/**
	 * @notice
	 * External function that allows the operator to send a staking command to the contract
	 * @param _amount Amount of ether to be staked
	 */
	function sendStakingCommand(uint256 _amount) external onlyOperator whenNotPaused {
		uint256 epoch = withdrawalEpoch;
		if (statusPerEpoch[epoch] != WithdrawalStatus.STANDBY) revert ErrWithdrawalEpochAlreadyEngaged();
		_sendStakingCommand(_amount);
	}

	/**  
	 * @notice
	 * External function that initiaties a withdrawal period.
	 * Price per share is locked for specific epoch to be used to users to redeem their strETH
	 */
	function initiateWithdrawalEpoch() external onlyOperator whenNotPaused {
		if (statusPerEpoch[withdrawalEpoch] != WithdrawalStatus.STANDBY) revert ErrWithdrawalEpochAlreadyEngaged();
		uint256 epoch = withdrawalEpoch;
		uint256 etherNeeded = previewRedeem(lockedstrETHPerEpoch[epoch]);

		statusPerEpoch[epoch] = WithdrawalStatus.INITIATED;
		emit WithdrawalProcessInitiated(epoch, etherNeeded);
	}

	/**  
	 * @notice
	 * External function that allows the operator to send an unstaking command to the contract
	 * @param _amount Amount of ether to be unstaked
	 */
	function submitUnstakeAction(uint256 _amount) external onlyOperator whenNotPaused {
		uint256 epoch = withdrawalEpoch;
		if (statusPerEpoch[epoch] != WithdrawalStatus.INITIATED) revert ErrWithdrawalEpochNotInitiated();
		_sendUnstakingCommand(_amount);
		statusPerEpoch[epoch] = WithdrawalStatus.UNSTAKE_ACTION_BROADCASTED;
	}

	/**  
	 * @notice
	 * External function that finalises a withdrawal period.
	 * Enough bridge operators must call this function to change the state of the withdrawal to finalised
	 * @param _tvl TVL of the epoch
	 */
	function submitTVLEpochVote(uint256 _tvl) external whenNotPaused {
		uint256 epoch = withdrawalEpoch;

		if (statusPerEpoch[epoch] == WithdrawalStatus.UNSTAKE_ACTION_BROADCASTED) revert ErrWithdrawalEpochNotInitiated();
		_submitVote(epoch, msg.sender);
		if (tvlPerEpoch[epoch] == 0) tvlPerEpoch[epoch] = _tvl;
		if (tvlPerEpoch[epoch] != _tvl) revert ErrWrongTVLSubmission();
		if (weightsPerEpoch[epoch] >= weightNeeded) {
			totalValueOnETH = tvlPerEpoch[epoch];
			statusPerEpoch[withdrawalEpoch++] = WithdrawalStatus.FINALISED;
			lockedPricePerSharePerEpoch[epoch] = LockedPricePerShare(totalSupply(), totalAssets());
			IERC20(asset()).transfer(escrow, previewRedeem(lockedstrETHPerEpoch[epoch]));
		}
	}

	/**  
	 * @notice
	 * Following 3 functions have bene overidden to prevent unintended deposit or withdrawal effects
	 */
	function mint(uint256 shares, address receiver) public override returns (uint256) {}
	function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {}
	function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {}

	function deposit(uint256 _amount) external {
		deposit(_amount, msg.sender);
	}

	function deposit(uint256 _amount, address _to) public override whenNotPaused returns (uint256) {
		return super.deposit(_amount, _to);
	}

	/**  
	 * @notice
	 * External function that allows a user to lock their strETH to be claimed into WETH at the end of the withdrawal period
	 * @param _shares Amount of shares to be locked to be claimed once withdrawal period is over
	 */
	function requestWithdrawal(uint256 _shares) external whenNotPaused {
		uint256 epoch = withdrawalEpoch;
		WithdrawalRequest storage request = withdrawalRequestsPerEpoch[epoch][msg.sender];

		if (statusPerEpoch[epoch] != WithdrawalStatus.STANDBY) revert ErrWithdrawalProcessInitiated();
		request.shares += _shares;
		lockedstrETHPerEpoch[epoch] += _shares;
		_transfer(msg.sender, address(this), _shares);
		emit WithdrawalRequested(msg.sender, epoch, _shares);
	}

	/**  
	 * @notice
	 * External function that allows a user redeem their strETH into WETH based on the price per share locked during initiation of withdrawal
	 * @param _epoch Epoch form which to redeem strETH into WETH
	 */

	function redeem(uint256 _epoch) external whenNotPaused {
		uint256 epoch = withdrawalEpoch;
		WithdrawalRequest storage request = withdrawalRequestsPerEpoch[_epoch][msg.sender];
		if (request.fulfilled) revert ErrRequestFulfilled();
		if (statusPerEpoch[_epoch] != WithdrawalStatus.FINALISED) revert ErrWithdrawalProcessNotFinalised();

		uint256 shares = request.shares;
		_burn(address(this), shares);
		request.fulfilled = true;
		LockedPricePerShare memory lockLog = lockedPricePerSharePerEpoch[_epoch];
		uint256 epochPricePerShare = _convertToAssets(shares, lockLog.assetSupply, lockLog.shareSupply);
		uint256 assets = shares * epochPricePerShare / 1e18;
		IERC20(asset()).transferFrom(escrow, msg.sender, assets);
		emit WithdrawalClaimed(msg.sender, epoch, shares, epochPricePerShare);
	}

	function _submitVote(uint256 _epoch, address _operator) internal {
		IBridgeManager manager = IBridgeManager(IRoninGateway(gateway).getContract(uint8(11)));
		uint256 operatorWeight = manager.getBridgeOperatorWeight(_operator);
		if (operatorWeight == 0) revert ErrInvalidBridgeOperator();
		if (votesPerEpoch[_epoch][_operator]) revert ErrOperatorHasAlreadyVoted();

		votesPerEpoch[_epoch][_operator] = true;
		weightsPerEpoch[_epoch] += operatorWeight;
	}

    function _convertToAssets(uint256 shares, uint256 totalAssets, uint256 totalShares) internal view virtual returns (uint256) {
        return shares.mulDiv(totalAssets + 1, totalShares + 10 ** _decimalsOffset(), Math.Rounding.Down);
    }
}