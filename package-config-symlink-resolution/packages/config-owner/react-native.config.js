const isNumber = require("is-number");

module.exports = {
  dependencyResolutionWorks: isNumber(123),
  resolvedDependency: require.resolve("is-number"),
};
