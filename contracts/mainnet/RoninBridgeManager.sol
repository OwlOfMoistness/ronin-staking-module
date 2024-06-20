// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "../../interfaces/IRoninGateway.sol";
import "./QuorumManager.sol";

error ErrRoninBridge();

enum ContractType {
  /*  0 */ UNKNOWN,
  /*  1 */ PAUSE_ENFORCER,
  /*  2 */ BRIDGE,
  /*  3 */ BRIDGE_TRACKING,
  /*  4 */ GOVERNANCE_ADMIN,
  /*  5 */ MAINTENANCE,
  /*  6 */ SLASH_INDICATOR,
  /*  7 */ STAKING_VESTING,
  /*  8 */ VALIDATOR,
  /*  9 */ STAKING,
  /* 10 */ RONIN_TRUSTED_ORGANIZATION,
  /* 11 */ BRIDGE_MANAGER,
  /* 12 */ BRIDGE_SLASH,
  /* 13 */ BRIDGE_REWARD,
  /* 14 */ FAST_FINALITY_TRACKING,
  /* 15 */ PROFILE
}

abstract contract RoninBridgeManager is QuorumManager {
	// keccak256("strETHVault")
	bytes32 constant public STR_ETH_VAULT_HASH = 0x542cc283fb01d7a74f3c04ce5ca22b24f40d94e61fb666d69f66ee87a5405c32;
	address immutable public RONIN_BRIDGE;


	address public strETHVault;
	uint256 _updateCounter;

	constructor(address _bridge) {
		RONIN_BRIDGE= _bridge;
	}

	function _getBridgeManager() internal view returns(address){
		return IRoninGateway(RONIN_BRIDGE).getContract(uint8(ContractType.BRIDGE_MANAGER));
	}

	/**  
	 * @notice
	 * Updates the address of the strETH vault via bridge operator quorum
	 * @param _strETHVault Address of the strETH vault
	 * @param _signatures Signatures of the bridge operators for quorum
	 */
	function updateStrETHVault(address _strETHVault, IRoninGateway.Signature[] memory _signatures) external {
		_validateSignatures(_strETHVault, _updateCounter++, STR_ETH_VAULT_HASH, _getBridgeManager(), _signatures);
		strETHVault = _strETHVault;
	}

	/**  
	 * @notice
	 * Internal function that fetches ether from the ronin bridge sent from Ronin
	 * @param _receipt Receipt of the request
	 * @param _signatures Signatures of the request
	 */
	function _requestEtherFromBridge(IRoninGateway.Receipt calldata _receipt, IRoninGateway.Signature[] calldata _signatures) internal {
		if (_signatures.length != 0)
			IRoninGateway(RONIN_BRIDGE).submitWithdrawal(_receipt, _signatures);
	}

	/**  
	 * @notice
	 * Internal function that sends back ether to the strETH vault on Ronin
	 * @param _amount Amount of ether to payback
	 */
	function _paybackBridge(uint256 _amount) internal {
		IRoninGateway.Request memory request = IRoninGateway.Request({
			recipientAddr: strETHVault,
			tokenAddr: address(0),
			info: IRoninGateway.Info({
				erc: IRoninGateway.Standard.ERC20,
				id: 0,
				quantity: _amount
			})
		});
		IRoninGateway(RONIN_BRIDGE).requestDepositFor(request);
	}
}