import type { Sidebar } from "vocs";

export const sidebar = {
	"/": [
		{
			text: "Hello Zabi",
			items: [{ text: "Overview", link: "/" }],
		},
		{
			text: "Integration",
			items: [{ text: "Integrating Zabi", link: "/integration" }],
		},
		{
			text: "Clients",
			collapsed: true,
			items: [
				{
					text: "HTTP",
					link: "/api/clients/Client",
				},
				{
					text: "Websocket",
					link: "/api/clients/Websocket",
				},
				{
					text: "IPC",
					link: "/api/clients/IPC",
				},
				{
					text: "Block Explorer",
					link: "/api/clients/BlockExplorer",
				},
				{
					text: "Wallet",
					link: "/api/clients/wallet",
				},
				{
					text: "Contract",
					link: "/api/clients/contract",
				},
				{
					text: "ENS",
					link: "/api/clients/ens/ens",
				},
				{
					text: "Multicall",
					link: "/api/clients/multicall",
				},
				{
					text: "OP L1 Public Client",
					link: "/api/clients/optimism/clients/L1PubClient",
				},
				{
					text: "OP L2 Public Client",
					link: "/api/clients/optimism/clients/L2PubClient",
				},
				{
					text: "OP L1 Wallet Client",
					link: "/api/clients/optimism/clients/L1WalletClient",
				},
				{
					text: "OP L2 Wallet Client",
					link: "/api/clients/optimism/clients/L2WalletClient",
				},
				{
					text: "Test Clients",
					collapsed: true,
					items: [
						{
							text: "Anvil",
							link: "/api/tests/Anvil",
						},
						{
							text: "Hardhat",
							link: "/api/tests/Hardhat",
						},
					],
				},
			],
		},
		{
			text: "ABI Utilities",
			collapsed: true,
			items: [
				{
					text: "ABI Encode",
					link: "/api/encoding/encoder",
				},
				{
					text: "ABI Encode Logs",
					link: "/api/encoding/logs",
				},
				{
					text: "ABI Decode Parameter",
					link: "/api/decoding/decoder",
				},
				{
					text: "ABI Decode Logs",
					link: "/api/decoding/logs_decode",
				},
				{
					text: "EIP712",
					link: "/api/abi/eip712",
				},
			],
		},
		{
			text: "ABI Types",
			collapsed: true,
			items: [
				{
					text: "Abi",
					link: "/api/abi/abi",
				},
				{
					text: "ABI Parameter",
					link: "/api/abi/abi_parameter",
				},
				{
					text: "Parameter Type",
					link: "/api/abi/param_type",
				},
			],
		},
		{
			text: "Zabi Types",
			collapsed: true,
			items: [
				{
					text: "Block",
					link: "/api/types/block",
				},
				{
					text: "Chain Config",
					link: "/api/clients/network",
				},
				{
					text: "Transaction",
					link: "/api/types/transaction",
				},
				{
					text: "Transaction Pool",
					link: "/api/types/txpool",
				},
				{
					text: "Proofs",
					link: "/api/types/proof",
				},
				{
					text: "Syncing",
					link: "/api/types/syncing",
				},
				{
					text: "Ethereum",
					link: "/api/types/ethereum",
				},
				{
					text: "Logs",
					link: "/api/types/log",
				},
				{
					text: "Block Explorer",
					link: "/api/types/explorer",
				},
				{
					text: "Op Stack Transaction",
					link: "/api/clients/optimism/types/transaction",
				},
				{
					text: "Op Stack General Types",
					link: "/api/clients/optimism/types/types",
				},
				{
					text: "Op Stack Withdrawl",
					link: "/api/clients/optimism/types/withdrawl",
				},
			],
		},
		{
			text: "Human readable Parsing",
			collapsed: true,
			items: [
				{
					text: "Human Readable",
					link: "/api/human-readable/abi_parsing",
				},
				{
					text: "Parser",
					link: "/api/human-readable/Parser",
				},
				{
					text: "Lexer",
					link: "/api/human-readable/lexer",
				},
				{
					text: "Solidity tokens",
					link: "/api/human-readable/tokens",
				},
			],
		},
		{
			text: "Utilities",
			collapsed: true,
			items: [
				{
					text: "General utilities",
					collapsed: true,
					items: [
						{
							text: "General",
							link: "/api/utils/utils",
						},
						{
							text: "Op Stack",
							link: "/api/clients/optimism/utils",
						},
						{
							text: "Ens",
							link: "/api/clients/ens/ens_utils",
						},
					],
				},
				{
					text: "Client",
					collapsed: true,
					items: [
						{
							text: "Ipc Reader",
							link: "/api/clients/ipc_reader",
						},
						{
							text: "Url Writer",
							link: "/api/clients/url",
						},
					],
				},
				{
					text: "Encoding",
					items: [
						{
							text: "RLP Encoding",
							link: "/api/encoding/rlp",
						},
						{
							text: "RLP Decode",
							link: "/api/decoding/rlp_decode",
						},
						{
							text: "SSZ Encoding",
							link: "/api/encoding/ssz",
						},
						{
							text: "SSZ Decode",
							link: "/api/decoding/ssz_decode",
						},
					],
				},
				{
					text: "Transaction",
					items: [
						{
							text: "Parse",
							link: "/api/decoding/parse_transaction",
						},
						{
							text: "Parse Deposit Transaction",
							link: "/api/clients/optimism/parse_deposit",
						},
						{
							text: "Serialize",
							link: "/api/encoding/serialize",
						},
						{
							text: "Serialize Deposit Transaction",
							link: "/api/clients/optimism/serialize_deposit",
						},
					],
				},
				{
					text: "Crypto",
					items: [
						{
							text: "ECDSA Signer",
							link: "/api/crypto/Signer",
						},
						{
							text: "BIP32 HD Wallets",
							link: "/api/crypto/hdwallet",
						},
						{
							text: "BIP39 Mnemonic Wallets",
							link: "/api/crypto/mnemonic",
						},
						{
							text: "Signature Types",
							link: "/api/crypto/signature",
						},
					],
				},
				{
					text: "EIP 4844",
					link: "/api/c-kzg-4844/ckzg4844",
				},
				{
					text: "Testing",
					items: [
						{
							text: "Value Generator",
							link: "/api/tests/generator",
						},
						{
							text: "Cli Parser",
							link: "/api/tests/args",
						},
					],
				},
			],
		},
		{
			text: "Meta Programming",
			collapsed: true,
			items: [
				{
					text: "Abi",
					link: "/api/meta/abi",
				},
				{
					text: "Json",
					link: "/api/meta/json",
				},
				{
					text: "Utils",
					link: "/api/meta/utils",
				},
			],
		},
		{
			text: "EVM Interpreter",
			collapsed: true,
			items: [
				{
					text: "Interpreter",
					link: "/api/evm/Interpreter",
				},
				{
					text: "Memory",
					link: "/api/evm/memory",
				},
				{
					text: "Interpreter actions",
					link: "/api/evm/actions",
				},
				{
					text: "Opcodes",
					link: "/api/evm/opcodes",
				},
				{
					text: "Specification",
					link: "/api/evm/Specification",
				},
				{
					text: "Bytecode",
					link: "/api/evm/bytecode",
				},
				{
					text: "Bytecode Analysis",
					link: "/api/evm/analysis",
				},
				{
					text: "Contract",
					link: "/api/evm/contract",
				},
				{
					text: "Enviroment",
					link: "/api/evm/enviroment",
				},
				{
					text: "Gas Tracker",
					link: "/api/evm/gas_tracker",
				},
				{
					text: "Instructions",
					items: [
						{
							text: "Arithmetic",
							link: "/api/evm/instructions/arithmetic",
						},
						{
							text: "Bitwise",
							link: "/api/evm/instructions/bitwise",
						},
						{
							text: "Contract",
							link: "/api/evm/instructions/contract",
						},
						{
							text: "Control",
							link: "/api/evm/instructions/control",
						},
						{
							text: "Enviroment",
							link: "/api/evm/instructions/enviroment",
						},
						{
							text: "Host",
							link: "/api/evm/instructions/host",
						},
						{
							text: "Memory",
							link: "/api/evm/instructions/memory",
						},
						{
							text: "Stack",
							link: "/api/evm/instructions/stack",
						},
						{
							text: "System",
							link: "/api/evm/instructions/system",
						},
					],
				},
			],
		},
	],
} satisfies Sidebar;
