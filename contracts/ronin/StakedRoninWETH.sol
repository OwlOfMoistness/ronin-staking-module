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

error ErrRequestFulfilled();
error ErrWithdrawalProcessInitiated();
error ErrWithdrawalProcessNotFinalised();
error ErrWithdrawalEpochNotInitiated();

enum WithdrawalStatus {
	STANDBY,
	INITIATED,
	FINALISED
}

contract StakedRoninWETH is ERC4626, Ownable {

	struct WithdrawalRequest {
		bool fulfilled;
		uint256 shares;
	}


	uint256 public cumulativeWETHStaked;
	uint256 public withdrawalEpoch;
	uint256 public depositLimit;

	mapping(uint256 => uint256) public lockedPricePerSharePerEpoch;
	mapping(uint256 => mapping(address => WithdrawalRequest)) public withdrawalRequestsPerEpoch;
	mapping(uint256 => uint256) public lockedstrETHPerEpoch;
	mapping(uint256 => WithdrawalStatus) public statusPerEpoch;

	event WithdrawalRequested(address indexed requester, uint256 indexed epoch, uint256 amount);
	event WithdrawalCancelled(address indexed requester, uint256 indexed epoch, uint256 amount);
	event WithdrawalClaimed(address indexed claimer, uint256 indexed epoch, uint256 amount, uint256 pricePerShare);
	event WithdrawalProcessInitiated(uint256 indexed epoch, uint256 wethRequired);

	constructor(address _weth)
		ERC4626(IERC20(_weth))
		ERC20("Staked Ronin Ether", "strETH") {}

	function setDepositLimit(uint256 _limit) external onlyOwner {
		depositLimit = _limit;
	}

	function maxDeposit(address) public view virtual override returns (uint256) {
		uint256 shares = totalSupply();
		if (shares == 0) return depositLimit;
		uint256 assets = previewRedeem(shares); 
		return assets > depositLimit ? 0 : (depositLimit - assets);
	}

	function settleEpochPricePerSharePeriod(bytes[] calldata _signatures) external {
		// TODO add governance check to make sure only contract that has been updated by bridge operators can send final price per share
		uint256 epoch = withdrawalEpoch++;
		if (statusPerEpoch[epoch] == WithdrawalStatus.INITIATED) revert ErrWithdrawalEpochNotInitiated();

		lockedPricePerSharePerEpoch[epoch] = previewRedeem(1e18);
		statusPerEpoch[epoch] = WithdrawalStatus.FINALISED;
	}

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

	function claim(uint256 _epoch) external {
		uint256 epoch = withdrawalEpoch;
		WithdrawalRequest storage request = withdrawalRequestsPerEpoch[_epoch][msg.sender];
		if (request.fulfilled) revert ErrRequestFulfilled();
		if (statusPerEpoch[_epoch] != WithdrawalStatus.FINALISED) revert ErrWithdrawalProcessNotFinalised();

		uint256 shares = request.shares;
		uint256 epochPricePerShare = lockedPricePerSharePerEpoch[_epoch];
		uint256 assets = previewRedeem(shares);
		request.fulfilled = true;
		_burn(address(this), shares);
		IERC20(asset()).transfer(msg.sender, assets);
		emit WithdrawalClaimed(msg.sender, epoch, shares, epochPricePerShare);
	}

	function initiateWithdrawal() external {
		// TODO add governance check to make sure only contract that has been updated by bridge operators can send final price per share

		uint256 epoch = withdrawalEpoch;
		statusPerEpoch[epoch] = WithdrawalStatus.INITIATED;
		emit WithdrawalProcessInitiated(epoch, previewRedeem(lockedstrETHPerEpoch[epoch]));
	}
}