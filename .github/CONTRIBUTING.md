# Contributing

Thanks for your interest in contributing to zabi! Please take a moment to review this document **before submitting a pull request.**

If you want to contribute, but aren't sure where to start, you can create a [new discussion](https://github.com/Raiden1411/zabi/discussions).

> **Note**
>
> **Please ask first before starting work on any significant new features.**
>
> It's never a fun experience to have your pull request declined after investing time and effort into a new feature. To avoid this from happening, we request that contributors create a [feature request](https://github.com/Raiden1411/zabi/discussions/new?category=ideas) to first discuss any API changes or significant new ideas.

<br>

## Basic guide

This guide is intended to help you get started with contributing. By following these steps, you will understand the development process and workflow.

1. [Cloning the repository](#cloning-the-repository)
2. [Installing zig](#installing-zig)
3. [Installing Foundry](#installing-foundry)
4. [Setting up Foundry](#setting-up-foundry)
5. [Building Zabi](#building)
6. [Running the test suite](#running-the-test-suite)
7. [Writing documentation](#writing-documentation)
8. [Submitting a pull request](#submitting-a-pull-request)

---

### Cloning the repository

To start contributing to the project, clone it to your local machine using git:

```bash
git clone https://github.com/Raiden1411/zabi.git 
```

Or the [GitHub CLI](https://cli.github.com):

```bash
gh repo clone Raiden1411/zabi
```

<div align="right">
  <a href="#basic-guide">&uarr; back to top</a></b>
</div>

---

### Installing Zig

You can install zig using any package manager from your distribution in case you are on linux. Otherwise you can download the binaries [here](https://ziglang.org/download/).

You can also use [zvm](https://www.zvm.app/) which is the recommended way of managing you zig version installs.

---

### Installing Foundry

Zabi uses [Foundry](https://book.getfoundry.sh/) for testing. We run 3 local [Anvil](https://github.com/foundry-rs/foundry/tree/master/anvil) instance against a forked Ethereum node, where we can also use tools like [Forge](https://book.getfoundry.sh/forge/) to deploy test contracts to it.

Install Foundry using the following command:

```bash
curl -L https://foundry.paradigm.xyz | bash
```

---

### Setting up Foundry

To fork an Ethereum node, in a new terminal, run the following command:

```bash
anvil --fork-url https://<your-ethereum-rpc-node-endpoint> -p 6969 --ipc
```
which will start the service on `https://127.0.0.1:6969` and `/tmp/anvil.ipc`, which are the default addresses for the Zabi library test suite.

<div align="right">
  <a href="#basic-guide">&uarr; back to top</a></b>
</div>

---

### Building

Once you have cloned the repo and have the correct version of zig running on your computer you can now run `zig build` to ensure that everything gets built properly.

Zabi supports `version 0.13.0` of zig in seperate branches. You can checkout each seperate branch and work in those branches if that is your goal.

---

### Running the test suite

Before running the tests you will need add the url's to a `.env` file. Zabi has a `.env.local` example that you can use for this. After updating that file you will need to run this command to successfully run the tests `zig build test -freference-trace -Dload_variables` so that the executable has the necessary enviroment variables it needs so that it can reset the anvil instance that must be running.

You can also run `zig build coverage` for running a seperate set of tests that then get analized with kcov (make sure you have it installed.) or you can run `zig build bench` to run the coverage tests as a benchmark.

When adding new features or fixing bugs, it's important to add test cases to cover the new/updated behavior.

<div align="right">
  <a href="#basic-guide">&uarr; back to top</a></b>
</div>

---

### Writing documentation

Documentation is crucial to helping developers of all experience levels use zabi. zabi uses [Vocs](https://vocs.dev) and Markdown for the documentation site (located at [`docs`](../docs)). To start the site in dev mode, run:

```bash
pnpm dev 
```

Zabi use mostly auto-generated documentation from its source code. If you make a change to the code make sure that to run `zig build docs` in order to update any changes.
If you create a new file and want to add it to the website make to update `docs/sidebar.ts` to include it.

This is expected to be changed in the future.

<div align="right">
  <a href="#basic-guide">&uarr; back to top</a></b>
</div>

---

### Submitting a pull request

When you're ready to submit a pull request, you can follow these naming conventions:

- Pull request titles use the [Imperative Mood](https://en.wikipedia.org/wiki/Imperative_mood) (e.g., `Add something`, `Fix something`).

When you submit a pull request, GitHub will automatically lint, build, and test your changes. If you see an ❌, it's most likely a bug in your code. Please, inspect the logs through the GitHub UI to find the cause.

The CI might also fail sometimes when it comes to the test runner. If running doesn't fix the problem then it's most likely a bug in your code.

<div align="right">
  <a href="#basic-guide">&uarr; back to top</a></b>
</div>

---

<br>

<div>
  ✅ Now you're ready to contribute to zabi!
</div>

<div align="right">
  <a href="#advanced-guide">&uarr; back to top</a></b>
</div>

