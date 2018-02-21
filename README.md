# Payroll Dapp

This is Dapp that is meant to be used to pay employees on a payroll. This allows
for a payroll owner to add and remove employees to the payroll and set their salaries.
Employees can then collect their monthly paycheck by calling the payroll once a month
and also have the capability to determine how much of there salary is paid in a specific
token.

Some of the code in this project was borrowed from OpenZeppelin for the ERC20 tokens that
are used in the payroll. Along with that is the SafeMath library that ensures that we
can do some safe math operations.

## Setup

You should be able to set up all the dependencies needed by the project by running

```
$ npm install
```

## Testing

There is a test script already defined that will set up your test environment and
run all the unit tests for the payroll dapp.

```
$ npm run test
```

If you would like to run coverage tests that is also defined and can be ran by using
the coverage script:

```
$ npm run coverage
```

## LICENSE

MIT
