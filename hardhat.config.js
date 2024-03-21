/** @type import('hardhat/config').HardhatUserConfig */
require("@nomiclabs/hardhat-ethers");
module.exports = {
  solidity: "0.8.24",
  networks: {
    BNB_Testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: 97,
      accounts: ["5a01713ebfe789aa1a32bd5df9fce8f7e726adcfdf669aa778cd53e9f7ebb7c3"]
    },
  }
};
