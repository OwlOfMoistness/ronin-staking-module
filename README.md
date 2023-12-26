# REP-0009: Add Ether staking capability to the Ronin bridge on Ethereum network

## Preamble

<pre>
REP-0009
Title: Add Ether staking capability to the Ronin bridge on Ethereum network
Author: Owl Of Moistness (discord: owlofmoistness)
Type: Bridge Track
Status: Draft
Created: 2023-12-06
</pre>

## Abstract

REP-0009 describes the process of enabling staking capability with ether that is residing on the Ethereum network bridge via deposits into LSDs (Liquid Staking Derivates).
This will allow users that opt into this scheme to earn eth rewards via the value accrual of those LSDs.

## Rationale

As of today's writing, a little over 34,161 ether is seating on the Ronin Bridge V2 contract. With an average of 4% apy for staking ether via validation, the ether in the bridge could generate up to around 1,366 ether. Those rewards can be distributed to users as well the AXS treasury and bridge operators.


## Specification

The current proposed system involved the creation of a new ERC-4626 Tokenised vault contract on the Ronin network that will represent the reward accrual of ether on the Ethereum network.

The token representing the vault will be called Staked Ronin Ether (strETH). Over time strETH will increase with value as more ether rewards are realised.

An additional module should be added to the Ronin Bridge V2 contract on Ethereum network called the Staked Ether Manager (SEM) that will be responsible for depositing and withdrawing ether to and from different LSDs (Currently eligible projects would be Lido Finance, RocketPool and Frax Finance).


Users shall be able to deposit without any restrictions their WETH to obtain strETH until the deposit limit is reached. This limit can be updated at any given time to be increased or decreased. When WETH is deposited, it increments a `cumulativeWETHStaked` variable that will be sent to Ethereum to indicate how much ether can be used for staking. User shall be able to redeem their strETH back into WETH every cyclic withdrawal periods (every 7 days + Ethereum unwinding time).


A final requirement is necessary in the form of task required to be performed by Bridge operators. The operators will need to provide:

- Regular update of the cumulative amount of deposited WETH on the strETH contract from Ronin network  to the SEM module on Ethereum.
- Regular update of the the realised ether rewards from holding various LSDs that should trigger WETH minting in the strETH contract on Ronin network.
- Cyclic update of the required Ether to be withdrawn every Withdrawal period from the strETH contract on Ronin network to the SEM module on Ethereum
- Cyclic update of the finalisation of the Withdrawal period from the SEM module on Ethereum to the strETH contract on Ronin network

Operators will need to reach quorum to transfer information in between Ronin Network and Ethereum, acting as oracles.

A withdrawal cycle will occur like this:
1. During 7 days, users will be able to request their strETH to be redeemed. This action will lock their tokens into the contract and cannot be undone.
2. After the 7 days, the withdrawal request is initiated on Ronin network and an event is emitted providing the necessary ether to be withdrawn on Ethereum. This information will be relayed by the bridge operators
3. After receiving the Withdrawal Initiation event from ronin, the SEM will start the process of unwinding enough LSDs to obtain the required ether amount to be withdrawn. This may be instant or may take a few days to wait on the various withdrawal queues of the LSD protocols.
4. Once enough ether has been withdrawn, the SEM will relay a message that the withdrawal cycle has been finalised via an event. This information will be relayed by the bridge operators.
5. On reception of the withdrawal finalisation, the strETH contract locks the final `pricePerShare` for this withdrawal cycle, allowing all users that have requested a withdrawal to burn their strETH and redeem WETH. A new withdrawal cycle will now commence.

![Infographic explaining the flow of depositing and withdrawing ether from ronin into LSDs](./info_v2.png)

## Reference

ERC-4626 Tokenised Vault Standard: <https://ethereum.org/en/developers/docs/standards/tokens/erc-4626/> 

RocketPool Protocol: <https://docs.rocketpool.net/>

Lido Finance Protocol: <https://docs.lido.fi/>

Frax Finance Protocol: <https://docs.frax.finance/>

## Security analysis

There are 4 main risks that need to be handled correctly to keep this system as secure as possible.
1. **Bridge Upgrade**: We want to leave the  ronin bridge as unchanged as possible. To do this, the SEM module should not be deployed as an inheritance but as a standalone, immutable contract. The only required change on the bridge would be a function to enable the SEM to request for ether unconditionally. Only the SEM contract address should be able to call this function successfully.
2. **Ether flow on the SEM**: The ether received on the SEM can only go in 2 different places. Either deposited into LSDs or back into the bridge. SEM operators won't be able to do anything else. At worse SEM operators can only decide to do nothing, which means ether remain on the bridge if not queried to be deposited into LSDs or if during a withdrawal request, the procedure may take longer until an honest operator or Sky Mavis itself executes the necessary measures to withdraw ether from the LSDs.
3. **Bridge operator honesty**: This problem is in itself a core problem of the bridge initially. If malicious bridge operators decided to send wrong information back and forth between Ethereum and ronin, the bridge wouldn't operate. Nevertheless, measure can be taken to make sure that any information relayed by BOs from on chain to the other is within expected values. For example, the `cumulativeWETHStaked` variable relayed from Ronin to Ethereum can only be higher than the previously logged value.

I would also like to discuss the strength of having the SEM either on Ethereum or Ronin chain. Such a system would be possible by enabling LSDs bridging and forcing users to exchange their LSD for the strETH token.
**Ronin strengths**:
- Less security risks as the bridge would need to deposit their LSD on mainer therefore not needing any contract upgrade.
- Fewer bridge relayed messages. Would only need the latest price per share value of each LSD token to represent the realised ether gains.
- Quicker withdrawals processes (if not instant).

**Ronin Weakness**:
- Does not capture ether that is residing on the Ethereum gateway contract.
- People would need to withdraw their ether, deposit into an LSD and redeposit back into the gateway
- The AXS treasury holds a considerable amount of ether, having the SEM on ronin would not allow this ether to be staked into an LSD
- The amount of returned LSD would be lower than initially deposited. To understand this, follow this example: Alice deposits 100 wstETH into the the ronin gateway that are worth 100 eth. Lets assume wstETH returns are 4% apy. Given that some of the returns will be redirected to the treasury and operators, her final APY will be lower than 4%, lets say it is 3.75%. After one year, Alice decides to withdraw back her wstETH. 100 wstETH are now worth 104 ether but because ronin network takes a share, her final amount would be 103.75 ether which equates to returning 99.76 wstETH back. Psychologically, this might look negative to holders.

**Ethereum Pros**
- Captures the majority of users as ~72% of ether is not staked
- The flow of obtaining strETH is much simpler. Deposit ether on gateway, deposit WEHT for strETH on ronin.
- Any existing WETH holder on ronin can deposit their WETH into strETH.
- AXS treasury can deposit their WETH and benefit the ecosystem with even more incetivised gameplay.
- Redeeming strETH will signify a higher returned amount of WEHT, psycholigically making the user feel they've earned something.

**Ethereum cons**
- More security risks due to needed to upgrade the Ethereum gateway and making sure the SEM handles deposits, withdraws and exits of LSDs in a very secure way, without any way of loosing funds.
- More work needed on the Bridge operator software to capture all the events needed to the system to function.
- Withdrawals will be handled in cycles of multiple days to give enough time to withdraw from LSDs if needed.

## Economic analysis

Assuming all ether is staked at 4% apy, those 1366 ether can be split into 3 baskets of various weights:

- 80% of rewards will go back to strETH holders
- 15% of rewards will be sent to the AXS treasury to be used within the Ronin Ecosystem
- 5% will be used as motivation for SEM and bridge operators

Rewarding these 3 type of users should allow for strETH to become a widely adopted token on the ronin network to be implemented in various products like Katana DEX, form of payment in the mavis marketplace and more as the ecosystem matures.

Treasury share makes a lot of sense given the acceleration of the ronin ecosystem is onboarding more and more projects within their chain. Giving such projects grants in forms of strETH or giving it away under the condition of active gameplay which is Sky Mavis' vision will enable economical incentives to capture more players.

Finally this new system requires extra care from operators to make it run smoothly, rewarding them should also be part of the plan to ensure a stable service as it grows and matures.
Further expansions of this model can be done with USDC who can be deposited in Maker to generate dai and deposit it in the DSR to generate ~5%.

## License

The content is licensed under [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
