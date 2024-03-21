import { Sidebar } from "vocs";

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
			text: "Client",
			collapsed: true,
			items: [
				{
					text: "HTTP and Websocket",
					link: "/api/client/public/client",
				},
				{
					text: "Wallet",
					link: "/api/client/wallet/client",
				},
				{
					text: "Contract",
					link: "/api/client/contract/client",
				},
				{
					text: "OP Stack",
					link: "/api/client/op-stack/clients",
				},
			],
		},
		{
			text: "ABI Utilities",
			collapsed: true,
			items: [
				{
					text: "ABI Encode Parameters",
					link: "/api/abi_utils/encode_parameters",
				},
				{
					text: "ABI Encode Function",
					link: "/api/abi_utils/encode_function",
				},
				{
					text: "ABI Encode Error",
					link: "/api/abi_utils/encode_error",
				},
				{
					text: "ABI Encode Constructor",
					link: "/api/abi_utils/encode_constructor",
				},
				{
					text: "ABI Decode Parameters",
					link: "/api/abi_utils/decode_parameters",
				},
				{
					text: "ABI Decode Function",
					link: "/api/abi_utils/decode_function",
				},
				{
					text: "ABI Decode Error",
					link: "/api/abi_utils/decode_error",
				},
				{
					text: "ABI Decode Constructor",
					link: "/api/abi_utils/decode_constructor",
				},
				{
					text: "Types",
					link: "/api/abi_utils/types",
				},
			],
		},
		{
			text: "ABI Types",
			collapsed: true,
			items: [
				{
					text: "Function",
					link: "/api/abi/function",
				},
				{
					text: "Event",
					link: "/api/abi/event",
				},
				{
					text: "Error",
					link: "/api/abi/error",
				},
				{
					text: "Constructor",
					link: "/api/abi/constructor",
				},
				{
					text: "Receive",
					link: "/api/abi/receive",
				},
				{
					text: "Fallback",
					link: "/api/abi/fallback",
				},
				{
					text: "Abi",
					link: "/api/abi/abi",
				},
				{
					text: "ABI Parameter",
					link: "/api/abi/parameters",
				},
			],
		},
		{
			text: "Human readable",
			collapsed: true,
			items: [
				{
					text: "Human Readable",
					link: "/api/abi/human",
				},
			],
		},
		{
			text: "EIP712",
			collapsed: true,
			items: [
				{
					text: "EIP712 Utils",
					link: "/api/abi/eip712",
				},
			],
		},
		{
			text: "Utilities",
			collapsed: true,
			items: [
				{
					text: "Address",
					items: [
						{
							text: "isAddress",
							link: "/api/utilities/address/isAddress",
						},
						{
							text: "isHash",
							link: "/api/utilities/address/isHash",
						},
						{
							text: "toChecksum",
							link: "/api/utilities/address/toChecksum",
						},
					],
				},
				{
					text: "Units",
					items: [
						{
							text: "parseGwei",
							link: "/api/utilities/units/parseGwei",
						},
						{
							text: "parseEther",
							link: "/api/utilities/units/parseEther",
						},
					],
				},
				{
					text: "Encoding",
					items: [
						{
							text: "RLP Encoding",
							link: "/api/utilities/encoding/rlp_encode",
						},
						{
							text: "RLP Decode",
							link: "/api/utilities/encoding/rlp_decode",
						},
						{
							text: "SSZ Encoding",
							link: "/api/utilities/encoding/ssz_encode",
						},
						{
							text: "SSZ Decode",
							link: "/api/utilities/encoding/ssz_decode",
						},
					],
				},
				{
					text: "Signature",
					items: [
						{
							text: "Signature",
							link: "/api/utilities/signature/signature",
						},
						{
							text: "Signer",
							link: "/api/utilities/signature/signer",
						},
					],
				},
				{
					text: "Transaction",
					items: [
						{
							text: "Parse",
							link: "/api/utilities/transaction/parse",
						},
						{
							text: "Serialize",
							link: "/api/utilities/transaction/serialize",
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
					text: "Meta Functions",
					link: "/api/meta/metaprogramming",
				},
			],
		},
	],
} satisfies Sidebar;
