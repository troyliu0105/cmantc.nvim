#pragma once

namespace math {

class Vector {
public:
    double x;
    double y;

    Vector();
    Vector(double x, double y);

    double magnitude() const;
};

Vector add(const Vector& a, const Vector& b);

}
