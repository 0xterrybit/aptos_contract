import asyncio
import os
import sys

from aptos_sdk.account import Account
from aptos_sdk.account_address import AccountAddress
from aptos_sdk.aptos_cli_wrapper import AptosCLIWrapper

from aptos_sdk.async_client import FaucetClient, RestClient
from aptos_sdk.bcs import Serializer
from aptos_sdk.package_publisher import PackagePublisher
from aptos_sdk.transactions import (
    EntryFunction,
    TransactionArgument,
    TransactionPayload,
)
from aptos_sdk.type_tag import StructTag, TypeTag

contract_address = "0x9e54d3231b270990fde73545f034dfa771696759e4f40ef8d5fc214cf88b4c6f"


class MarketClient(RestClient):


    async def add_new_vault(self, sender: Account, collateral_type, weight, max_interval, max_price_confidence, feeder, param_multiplier) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "add_new_vault",
            [TypeTag(StructTag.from_str(collateral_type))],
            [
                TransactionArgument(weight, Serializer.u256),
                TransactionArgument(max_interval, Serializer.u64),
                TransactionArgument(max_price_confidence, Serializer.u64),
                TransactionArgument(feeder, Serializer.sequence_serializer(Serializer.u8)),
                TransactionArgument(param_multiplier, Serializer.u256)
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def add_new_symbol(self, sender: Account, index, direction, max_interval, max_price_confidence, feeder, param_multiplier, 
                             param_max, max_leverage, min_holding_duration, max_reserved_multiplier, min_collateral_value, 
                             oepn_fee_bps, decrease_fee_bps, liquidation_threshold, liquidation_bonus) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "add_new_symbol",
            [TypeTag(StructTag.from_str(index)), TypeTag(StructTag.from_str(contract_address+"::pool::"+direction))],
            [
                TransactionArgument(max_interval, Serializer.u64),
                TransactionArgument(max_price_confidence, Serializer.u64),
                TransactionArgument(feeder, Serializer.sequence_serializer(Serializer.u8)),
                TransactionArgument(param_multiplier, Serializer.u256),
                TransactionArgument(param_max, Serializer.u128),
                TransactionArgument(max_leverage, Serializer.u64),
                TransactionArgument(min_holding_duration, Serializer.u64),
                TransactionArgument(max_reserved_multiplier, Serializer.u64),
                TransactionArgument(min_collateral_value, Serializer.u256),
                TransactionArgument(oepn_fee_bps, Serializer.u128),
                TransactionArgument(decrease_fee_bps, Serializer.u128),
                TransactionArgument(liquidation_threshold, Serializer.u128),
                TransactionArgument(liquidation_bonus, Serializer.u128)
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def add_collateral_to_symbol(self, sender: Account, collateral, index, direction) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "add_collateral_to_symbol",
            [TypeTag(StructTag.from_str(collateral)), TypeTag(StructTag.from_str(index)), TypeTag(StructTag.from_str(contract_address+"::pool::"+direction))],
            []
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def replace_symbol_feeder(self, sender: Account, index, direction, feeder, max_interval, max_price_confidence) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "replace_symbol_feeder",
            [TypeTag(StructTag.from_str(index)), TypeTag(StructTag.from_str(contract_address+"::pool::"+direction))],
            [
                TransactionArgument(feeder, Serializer.sequence_serializer(Serializer.u8)),
                TransactionArgument(max_interval, Serializer.u64),
                TransactionArgument(max_price_confidence, Serializer.u64),
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def deposit(self, sender: Account, collateral, deposit_amount, min_amount_out) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "deposit",
            [TypeTag(StructTag.from_str(collateral))],
            [
                TransactionArgument(deposit_amount, Serializer.u64),
                TransactionArgument(min_amount_out, Serializer.u64),
                TransactionArgument([], Serializer.sequence_serializer(Serializer.sequence_serializer(Serializer.u8)))
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def withdraw(self, sender: Account, collateral, lp_burn_amount, min_amount_out) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "withdraw",
            [TypeTag(StructTag.from_str(collateral))],
            [
                TransactionArgument(lp_burn_amount, Serializer.u64),
                TransactionArgument(min_amount_out, Serializer.u64),
                TransactionArgument([], Serializer.sequence_serializer(Serializer.sequence_serializer(Serializer.u8)))
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def swap(self, sender: Account, source, destination, amount_in, min_amount_out) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "swap",
            [TypeTag(StructTag.from_str(source), TypeTag(StructTag.from_str(destination)))],
            [
                TransactionArgument(amount_in, Serializer.u64),
                TransactionArgument(min_amount_out, Serializer.u64),
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def open_position(self, sender: Account, collateral, index, direction, fee, trade_level, open_amount, 
                            reserve_amount, collateral_amount, fee_amount, collateral_price_threshold, limited_index_price) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "open_position",
            [TypeTag(StructTag.from_str(collateral)), TypeTag(StructTag.from_str(index)), TypeTag(StructTag.from_str(contract_address+"::pool::"+direction)), TypeTag(StructTag.from_str(fee))],
            [
                TransactionArgument(trade_level, Serializer.u8),
                TransactionArgument(open_amount, Serializer.u64),
                TransactionArgument(reserve_amount, Serializer.u64),
                TransactionArgument(collateral_amount, Serializer.u64),
                TransactionArgument(fee_amount, Serializer.u64),
                TransactionArgument(collateral_price_threshold, Serializer.u256),
                TransactionArgument(limited_index_price, Serializer.u256)
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def decrease_position(self, sender: Account, collateral, index, direction, fee, trade_level, fee_amount, 
                            take_profit, decrease_amount, collateral_price_threshold, limited_index_price, position_num) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "decrease_position",
            [TypeTag(StructTag.from_str(collateral)), TypeTag(StructTag.from_str(index)), TypeTag(StructTag.from_str(contract_address+"::pool::"+direction)), TypeTag(StructTag.from_str(fee))],
            [
                TransactionArgument(trade_level, Serializer.u8),
                TransactionArgument(fee_amount, Serializer.u64),
                TransactionArgument(take_profit, Serializer.bool),
                TransactionArgument(decrease_amount, Serializer.u64),
                TransactionArgument(collateral_price_threshold, Serializer.u256),
                TransactionArgument(limited_index_price, Serializer.u256),
                TransactionArgument(position_num, Serializer.u64)
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def execute_open_postion_order(self, sender: Account, collateral, index, direction, fee, owner, order_num) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "execute_open_position_order",
            [TypeTag(StructTag.from_str(collateral)), TypeTag(StructTag.from_str(index)), TypeTag(StructTag.from_str(contract_address+"::pool::"+direction)), TypeTag(StructTag.from_str(fee))],
            [
                TransactionArgument(owner, Serializer.struct),
                TransactionArgument(order_num, Serializer.u64)
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def execute_close_postion_order(self, sender: Account, collateral, index, direction, fee, owner, order_num, position_num) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "execute_decrease_position_order",
            [TypeTag(StructTag.from_str(collateral)), TypeTag(StructTag.from_str(index)), TypeTag(StructTag.from_str(contract_address+"::pool::"+direction)), TypeTag(StructTag.from_str(fee))],
            [
                TransactionArgument(owner, Serializer.struct),
                TransactionArgument(order_num, Serializer.u64),
                TransactionArgument(position_num, Serializer.u64)
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def pledge_in_position(self, sender: Account, collateral, index, direction, pledge_num, position_num) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "pledge_in_position",
            [TypeTag(StructTag.from_str(collateral)), TypeTag(StructTag.from_str(index)), TypeTag(StructTag.from_str(contract_address+"::pool::"+direction))],
            [
                TransactionArgument(pledge_num, Serializer.u64),
                TransactionArgument(position_num, Serializer.u64)
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def redeem_from_position(self, sender: Account, collateral, index, direction, redeem_num, position_num) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "redeem_from_position",
            [TypeTag(StructTag.from_str(collateral)), TypeTag(StructTag.from_str(index)), TypeTag(StructTag.from_str(contract_address+"::pool::"+direction))],
            [
                TransactionArgument(redeem_num, Serializer.u64),
                TransactionArgument(position_num, Serializer.u64)
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)

    async def liquidate_position(self, sender: Account, collateral, index, direction, owner, position_num) -> str:

        payload = EntryFunction.natural(
            contract_address+"::market",
            "liquidate_position",
            [TypeTag(StructTag.from_str(collateral)), TypeTag(StructTag.from_str(index)), TypeTag(StructTag.from_str(contract_address+"::pool::"+direction))],
            [
                TransactionArgument(owner, Serializer.struct),
                TransactionArgument(position_num, Serializer.u64)
            ]
        )
        signed_transaction = await self.create_bcs_signed_transaction(
            sender, TransactionPayload(payload)
        )
        return await self.submit_bcs_transaction(signed_transaction)


#
async def main():
    sender = Account.load_key("0x8dddb9887ed4d275536a05d47cbaf810dc8873f617080b3fdc6afd81ff73798d")
    NODE_URL = "https://fullnode.testnet.aptoslabs.com/v1"

    rest_client = MarketClient(NODE_URL)
    # txn_hash = await rest_client.add_new_vault(sender, "0x1::aptos_coin::AptosCoin", 100000000000000000, 2000, 18446744073709551615, list(bytes.fromhex("44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e")), 800000000000000)
    # txn_hash = await rest_client.add_new_vault(sender, "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::usdc::USDC", 100000000000000000, 2000, 18446744073709551615, list(bytes.fromhex("41f3625971ca2ed2263e78573fe5ce23e13d2558ed3f2e47ab0f84fb9e7ae722")), 800000000000000)
    # txn_hash = await rest_client.add_new_vault(sender, "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::usdt::USDT", 100000000000000000, 2000, 18446744073709551615, list(bytes.fromhex("1fc18861232290221461220bd4e2acd1dcdfbc89c84092c93c18bdc7756c1588")), 800000000000000)
    # txn_hash = await rest_client.add_new_symbol(sender, "0x1::aptos_coin::AptosCoin", "LONG", 2000, 18446744073709551615, list(bytes.fromhex("44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e")), 20000000000000000, 7500000000000000, 100, 20, 20, 500000000000000, 1000000000000000, 1000000000000000, 980000000000000000, 10000000000000000)
    # txn_hash = await rest_client.add_new_symbol(sender, "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::btc::BTC", "LONG", 2000, 18446744073709551615, list(bytes.fromhex("f9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b")), 20000000000000000, 7500000000000000, 100, 20, 20, 500000000000000, 1000000000000000, 1000000000000000, 980000000000000000, 10000000000000000)
    # txn_hash = await rest_client.add_new_symbol(sender, "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::ETH::ETH", "LONG", 2000, 18446744073709551615, list(bytes.fromhex("ca80ba6dc32e08d06f1aa886011eed1d77c77be9eb761cc10d72b7d0a2fd57a6")), 20000000000000000, 7500000000000000, 100, 20, 20, 500000000000000, 1000000000000000, 1000000000000000, 980000000000000000, 10000000000000000)
    # txn_hash = await rest_client.add_new_symbol(sender, "0x1::aptos_coin::AptosCoin", "SHORT", 2000, 18446744073709551615, list(bytes.fromhex("44a93dddd8effa54ea51076c4e851b6cbbfd938e82eb90197de38fe8876bb66e")), 20000000000000000, 7500000000000000, 100, 20, 20, 500000000000000, 1000000000000000, 1000000000000000, 980000000000000000, 10000000000000000)
    # txn_hash = await rest_client.add_new_symbol(sender, "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::btc::BTC", "SHORT", 2000, 18446744073709551615, list(bytes.fromhex("f9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b")), 20000000000000000, 7500000000000000, 100, 20, 20, 500000000000000, 1000000000000000, 1000000000000000, 980000000000000000, 10000000000000000)
    # txn_hash = await rest_client.add_new_symbol(sender, "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::ETH::ETH", "SHORT", 2000, 18446744073709551615, list(bytes.fromhex("ca80ba6dc32e08d06f1aa886011eed1d77c77be9eb761cc10d72b7d0a2fd57a6")), 20000000000000000, 7500000000000000, 100, 20, 20, 500000000000000, 1000000000000000, 1000000000000000, 980000000000000000, 10000000000000000)
    # txn_hash = await rest_client.add_collateral_to_symbol(sender, "0x1::aptos_coin::AptosCoin", "0x1::aptos_coin::AptosCoin", "SHORT")
    # txn_hash = await rest_client.add_collateral_to_symbol(sender,  "0x1::aptos_coin::AptosCoin", "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::btc::BTC", "SHORT")
    # txn_hash = await rest_client.add_collateral_to_symbol(sender, "0x1::aptos_coin::AptosCoin", "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::ETH::ETH",  "SHORT")
    # txn_hash = await rest_client.add_collateral_to_symbol(sender,  "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::usdc::USDC", "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::btc::BTC", "SHORT")
    # txn_hash = await rest_client.add_collateral_to_symbol(sender, "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::usdc::USDC", "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::ETH::ETH", "LONG")
    # txn_hash = await rest_client.add_collateral_to_symbol(sender,  "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::usdc::USDC", "0x1::aptos_coin::AptosCoin", "SHORT")
    # txn_hash = await rest_client.add_collateral_to_symbol(sender,  "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::usdt::USDT", "0x1::aptos_coin::AptosCoin", "SHORT")
    # txn_hash = await rest_client.add_collateral_to_symbol(sender, "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::usdc::USDC", "0x6f60af74988c64cd3b7c1e214697e6949db39c061d8d4cf59a7e2bd1b66c8bf0::ETH::ETH", "SHORT")
    # txn_hash = await rest_client.deposit(sender, "0x1::aptos_coin::AptosCoin", 100000000, 0)
    txn_hash = await rest_client.withdraw(sender, "0x1::aptos_coin::AptosCoin", 6000000, 0)
    # txn_hash = await rest_client.open_position(sender, "0x1::aptos_coin::AptosCoin", "0x1::aptos_coin::AptosCoin", "LONG", "0x1::aptos_coin::AptosCoin", 1, 1000000, 1000000, 1000000, 10, 8163025540, 8108650100000000000)
    # txn_hash = await rest_client.decrease_position(sender, "0x1::aptos_coin::AptosCoin", "0x1::aptos_coin::AptosCoin", "LONG", "0x1::aptos_coin::AptosCoin", 1, 100, False, 1000, 8163025540, 8108650100000000000, 0)
    # txn_hash = await rest_client.execute_open_postion_order(sender, "0x1::aptos_coin::AptosCoin", "0x1::aptos_coin::AptosCoin", "LONG", "0x1::aptos_coin::AptosCoin", sender.address(), 0)
    # txn_hash = await rest_client.pledge_in_position(sender, "0x1::aptos_coin::AptosCoin", "0x1::aptos_coin::AptosCoin", "LONG", 100000, 0)
    # txn_hash = await rest_client.redeem_from_position(sender, "0x1::aptos_coin::AptosCoin", "0x1::aptos_coin::AptosCoin", "LONG", 100000, 0)
    print(txn_hash)
#
#
if __name__ == "__main__":

    asyncio.run(main())