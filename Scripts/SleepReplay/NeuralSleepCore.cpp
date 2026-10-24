// Six-state model equations adapted from the public infant trajectory example.
// Copyright (c) 2023 Brain Modelling Group. MIT license: NeuralDynamics-LICENSE.txt.
// Upstream: https://github.com/brain-modelling-group/infant-sleep-trajectory
// This research bridge is not part of the app target.
#include <array>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
using State = std::array<double, 6>;
struct Parameters { double chi, mu, circadian, bias; };
static double firing(double v) {
    double z=(v-10)/3;
    double q=z>=0 ? 1/(1+std::exp(-z)) : std::exp(z)/(1+std::exp(z));
    return 360000*q;
}
static State derivative(double t, const State& y, const Parameters& p) {
    double clock=t-24*std::floor(t/24);
    double light=20+490*(std::tanh((clock*3600-28800)/6000)-std::tanh((clock*3600-61200)/6000));
    double alpha=.16*std::pow((y[0]>y[1] ? light : 0)/9500,.6);
    double B=(1-p.bias*y[4])*(1-p.bias*y[5])*19.9*alpha*(1-y[3]);
    double C=.5*(1+.8*y[5]-.47*y[4]);
    double qm=firing(y[0]), qv=firing(y[1]);
    return {360*(-y[0]-1.8/3600*qv+1.3),
        360*(-y[1]-2.1/3600*qm+y[2]+p.circadian*C-10.2),
        (-y[2]+p.mu/3600*qm)/p.chi,
        60*(alpha*(1-y[3])-.013*y[3]),
        std::acos(-1)/12*(.23*(y[4]-4.0/3*std::pow(y[4],3))-y[5]*(std::pow(24/(.99669*24.2),2)+.55*B)),
        std::acos(-1)/12*(y[4]+B)};
}
static State advance(double t, State y, double h, const Parameters& p) {
    State a=derivative(t,y,p),v;
    for(int k=0;k<6;k++)v[k]=y[k]+h*a[k]/2;
    State b=derivative(t+h/2,v,p);
    for(int k=0;k<6;k++)v[k]=y[k]+h*b[k]/2;
    State c=derivative(t+h/2,v,p);
    for(int k=0;k<6;k++)v[k]=y[k]+h*c[k];
    State d=derivative(t+h,v,p);
    for(int k=0;k<6;k++)y[k]+=h/6*(a[k]+2*b[k]+2*c[k]+d[k]);
    return y;
}
static void array_json(const std::vector<double>& v) {
    std::cout<<"[";for(size_t i=0;i<v.size();i++){if(i)std::cout<<",";std::cout<<v[i];}std::cout<<"]";
}
static void simulate(Parameters p, double hours, double seconds, double lower) {
    if(!(p.chi>0 && p.mu>0 && seconds>0 && hours>0))throw std::runtime_error("Invalid model arguments");
    State y={.6,-6.7,14.6,.35,-.86,-.59};
    double h=seconds/3600;long long steps=std::llround(hours/h);
    if(std::abs(steps*h-hours)>1e-8)throw std::runtime_error("Step must divide duration");
    bool window_wake=y[0]>y[1], captured=false;
    std::vector<double> onset,wake;
    for(long long i=0;i<steps;i++) {
        double t=i*h;
        if(!captured && t>=lower-1e-10){window_wake=y[0]>y[1];captured=true;}
        State next=advance(t,y,h,p);
        for(double v:next)if(!std::isfinite(v))throw std::runtime_error("Nonfinite model state");
        double before=y[0]-y[1], after=next[0]-next[1];
        if((before>0)!=(after>0)) {
            double event=t+h*before/(before-after);
            if(event>=lower) {
                if(before>0)onset.push_back(event-lower);else wake.push_back(event-lower);
            }
        }
        y=next;
    }
    std::cout<<"{\"parameters\":["<<p.chi<<","<<p.mu<<","<<p.circadian<<","<<p.bias<<"],\"initialWake\":"<<(window_wake?"true":"false")<<",\"onsetsHours\":";
    array_json(onset);std::cout<<",\"wakesHours\":";array_json(wake);std::cout<<",\"finalState\":[";
    for(int k=0;k<6;k++){if(k)std::cout<<",";std::cout<<y[k];}std::cout<<"]}";
}
int main(int argc,char** argv) {
    try {
        std::cout<<std::setprecision(17);
        if(argc==13 && std::string(argv[1])=="derivative") {
            Parameters p={std::stod(argv[2]),std::stod(argv[3]),std::stod(argv[4]),std::stod(argv[5])};
            State y;for(int k=0;k<6;k++)y[k]=std::stod(argv[7+k]);
            State d=derivative(std::stod(argv[6]),y,p);std::cout<<"[";for(int k=0;k<6;k++){if(k)std::cout<<",";std::cout<<d[k];}std::cout<<"]\n";
        } else if(argc==9 && std::string(argv[1])=="simulate") {
            Parameters p={std::stod(argv[2]),std::stod(argv[3]),std::stod(argv[4]),std::stod(argv[5])};
            simulate(p,std::stod(argv[6]),std::stod(argv[7]),std::stod(argv[8]));std::cout<<"\n";
        } else if(argc==4 && std::string(argv[1])=="bank") {
            std::ifstream in(argv[2]);if(!in)throw std::runtime_error("Missing parameter file");
            Parameters p;bool first=true;std::cout<<"[";
            while(in>>p.chi>>p.mu>>p.circadian>>p.bias) {
                if(!first)std::cout<<",";first=false;
                simulate(p,64*24,std::stod(argv[3]),49*24);
            }
            std::cout<<"]\n";
        } else throw std::runtime_error("Use derivative, simulate, or bank");
    } catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}
}
