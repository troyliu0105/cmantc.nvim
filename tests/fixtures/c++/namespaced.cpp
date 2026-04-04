#include "namespaced.hpp"

namespace math {

Vector::Vector() : x(0), y(0) {
}

Vector::Vector(double x_, double y_) : x(x_), y(y_) {
}

double Vector::magnitude() const {
    return x * x + y * y;
}

Vector add(const Vector& a, const Vector& b) {
    return Vector(a.x + b.x, a.y + b.y);
}

}
