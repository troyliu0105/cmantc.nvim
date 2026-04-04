#pragma once

template<typename T>
class Container {
public:
    Container();
    ~Container();

    void add(const T& value);
    T get(int index) const;

private:
    T data_[100];
    int size_;
};
