#ifndef PARAMETERS_HPP_
#define PARAMETERS_HPP_

#include <string>
#include <vector>
#ifdef CPP11
#include <unordered_map>
#include <tuple>
using std::unordered_map;
using std::tuple;
#else
#include <boost/unordered_map.hpp>
#include <boost/tuple/tuple.hpp>
using boost::unordered_map;
using boost::tuple;
#endif



class BoolParameter {
public:
	BoolParameter() {};
	BoolParameter(bool defaultValue);
	bool get();
	void set(bool value);
private:
	bool value;
};

class NumericParameter {
public:
	NumericParameter() {};
	NumericParameter(float defaultValue, float min, float max, float step);
	float get();
	void set(float value);
	bool validate(float value);
	float getMax() const;
	void setMax(float max);
	float getMin() const;
	void setMin(float min);
	float getStep() const;
	void setStep(float step);
private:
	float value;
	float min;
	float max;
	float step;
};

class StringParameter {
public:
	StringParameter() {};
	StringParameter(std::string defaultValue, std::vector<std::string> possibilities);
	std::string get();
	void set(std::string value);
	bool validate(std::string value);
	std::vector<std::string> getPossibilities() const;
private:
	std::string value;
	std::vector<std::string> possibilities;
};
typedef struct paramList {
	unordered_map<std::string, BoolParameter> bools;
	unordered_map<std::string, NumericParameter> numerics;
	unordered_map<std::string, StringParameter> strings;
} paramList;

paramList initParameters();
paramList setParameter(paramList parameters, std::string name, std::string value);
paramList getParameters(int argc, char ** argv);
float getParam(paramList parameters, std::string parameterName);
bool getParamBool(paramList parameters, std::string parameterName);
std::string getParamStr(paramList parameters, std::string parameterName);

#endif /* PARAMETERS_HPP_ */
