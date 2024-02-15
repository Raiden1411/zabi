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
	],
} satisfies Sidebar;
