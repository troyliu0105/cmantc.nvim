#pragma once

class Calculator {
public:
    Calculator();
    ~Calculator();

    int add(int a, int b);
    int subtract(int a, int b);
    virtual void reset();

private:
    int result_;
};
