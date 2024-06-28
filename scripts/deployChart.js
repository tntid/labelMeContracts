const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy ArtChartFactory
  const ArtChartFactory = await hre.ethers.getContractFactory("ArtChartFactory");
  const onlyAllowOwner = false; // Set this to true or false as needed
  const artChartFactory = await ArtChartFactory.deploy(onlyAllowOwner);

  await artChartFactory.waitForDeployment();

  console.log("ArtChartFactory deployed to:", await artChartFactory.getAddress());

  // Verify contract
  if (hre.network.name !== "hardhat" && hre.network.name !== "localhost") {
    console.log("Waiting for block confirmations...");
    
    await artChartFactory.deploymentTransaction().wait(5); // Wait for 5 block confirmations

    console.log("Verifying contract...");

    await hre.run("verify:verify", {
      address: await artChartFactory.getAddress(),
      constructorArguments: [onlyAllowOwner],
    });
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });