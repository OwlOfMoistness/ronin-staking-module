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
import "@openzeppelin/access/Ownable.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";

error ErrRequestFulfilled();
error ErrWithdrawalProcessInitiated();
error ErrWithdrawalProcessNotFinalised();
error ErrWithdrawalEpochNotInitiated();
error ErrInvalidOperator();

enum WithdrawalStatus {
	STANDBY,
	INITIATED,
	FINALISED
}

contract StakedRoninWETH is ERC4626, Ownable {
	using Math for uint256;

	struct WithdrawalRequest {
		bool fulfilled;
		uint256 shares;
	}

	struct LockedPricePerShare {
		uint256 shareSupply;
		uint256 assetSupply;
	}

	uint256 public cumulativeWETHStaked;
	uint256 public withdrawalEpoch;
	uint256 public depositLimit;

	mapping(uint256 => LockedPricePerShare) public lockedPricePerSharePerEpoch;
	mapping(uint256 => mapping(address => WithdrawalRequest)) public withdrawalRequestsPerEpoch;
	mapping(uint256 => uint256) public lockedstrETHPerEpoch;
	mapping(uint256 => WithdrawalStatus) public statusPerEpoch;

	mapping(address => bool) public operator;

	event WithdrawalRequested(address indexed requester, uint256 indexed epoch, uint256 amount);
	event WithdrawalCancelled(address indexed requester, uint256 indexed epoch, uint256 amount);
	event WithdrawalClaimed(address indexed claimer, uint256 indexed epoch, uint256 amount, uint256 pricePerShare);
	event WithdrawalProcessInitiated(uint256 indexed epoch, uint256 wethRequired);

	constructor(address _weth)
		ERC4626(IERC20(_weth))
		ERC20("Staked Ronin Ether", "strETH") {}

	modifier onlyOperator() {
		if (msg.sender != owner() || operator[msg.sender]) revert ErrInvalidOperator();
		_;
	}

	function updateOperator(address _operator, bool _value) external onlyOwner {
		operator[_operator] = _value;
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

	/**  
	 * @notice
	 * External function that initiaties a withdrawal period.
	 * Price per share is locked for specific ecpoch to be used to users to redeem their strETH
	 */
	function initiateWithdrawal() external onlyOperator{
		// TODO add governance check to make sure only contract that has been updated by bridge operators can send final price per share

		uint256 epoch = withdrawalEpoch;
		uint256 etherNeeded = previewRedeem(lockedstrETHPerEpoch[epoch]);
		statusPerEpoch[epoch] = WithdrawalStatus.INITIATED;
		lockedPricePerSharePerEpoch[epoch] = LockedPricePerShare(lockedstrETHPerEpoch[epoch], etherNeeded);
		emit WithdrawalProcessInitiated(epoch, etherNeeded);
	}

	/**  
	 * @notice
	 * External function that finalises a withdrawal period.
	 * Price per share is locked for specific ecpoch to be used to users to redeem their strETH
	 * @param _signatures signatures provided by bridge operators to enable this function to be executed.
	 * 					  If quorum if signatures is not reached, this functino will revert.
	 */
	function settleEpochPricePerSharePeriod(bytes[] calldata _signatures) external {
		// TODO add governance check to make sure only contract that has been updated by bridge operators can send final price per share
		uint256 epoch = withdrawalEpoch++;
		if (statusPerEpoch[epoch] == WithdrawalStatus.INITIATED) revert ErrWithdrawalEpochNotInitiated();
		statusPerEpoch[epoch] = WithdrawalStatus.FINALISED;
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

	function deposit(uint256 _amount, address _to) public override returns (uint256) {
		cumulativeWETHStaked += _amount;
		super.deposit(_amount, _to);
	}

	/**  
	 * @notice
	 * External function that allows a user to lock their strETH to be claimed into WETH at the end of the withdrawal period
	 * @param _shares Amount of shares to be locked to be claimed once withdrawal period is over
	 */
	function requestWithdrawal(uint256 _shares) external {
		uint256 epoch = withdrawalEpoch;
		WithdrawalRequest storage request = withdrawalRequestsPerEpoch[epoch][msg.sender];

		if (statusPerEpoch[epoch] != WithdrawalStatus.STANDBY) revert ErrWithdrawalProcessInitiated();
		// this check should never be true since finalisation of price increments the epoch counter
		if (request.fulfilled) revert ErrRequestFulfilled();
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

	function redeem(uint256 _epoch) external {
		uint256 epoch = withdrawalEpoch;
		WithdrawalRequest storage request = withdrawalRequestsPerEpoch[_epoch][msg.sender];
		if (request.fulfilled) revert ErrRequestFulfilled();
		if (statusPerEpoch[_epoch] != WithdrawalStatus.FINALISED) revert ErrWithdrawalProcessNotFinalised();

		uint256 shares = request.shares;
		LockedPricePerShare memory lockLog = lockedPricePerSharePerEpoch[_epoch];
		uint256 epochPricePerShare = _convertToAssets(shares, lockLog.assetSupply, lockLog.shareSupply);
		uint256 assets = shares * epochPricePerShare / 1e18;
		request.fulfilled = true;
		_burn(address(this), shares);
		IERC20(asset()).transfer(msg.sender, assets);
		emit WithdrawalClaimed(msg.sender, epoch, shares, epochPricePerShare);
	}

    function _convertToAssets(uint256 shares, uint256 totalAssets, uint256 totalShares) internal view virtual returns (uint256) {
        return shares.mulDiv(totalAssets + 1, totalShares + 10 ** _decimalsOffset(), Math.Rounding.Down);
    }
}