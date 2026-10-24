// Research-only initialization experiment; model equations remain shared.
// A neutral, assumed 07:00-19:00 wake schedule supplies initial slow states.
// Actual completed sleep intervals then force seven days before each query.
#define main neutral_core_main
#include "NeuralSleepCore.cpp"
#undef main
#include <algorithm>
struct LocalOffset { double t,hours; };
static std::vector<LocalOffset> localOffsets;
static double localTime(double t) {
    auto it=std::upper_bound(localOffsets.begin(),localOffsets.end(),t,
        [](double v,const LocalOffset& o){return v<o.t;});
    if(it==localOffsets.begin())throw std::runtime_error("Missing offset");
    return t+(--it)->hours;
}
static State rhsObserved(double t,State y,const Parameters& p,int observed,bool neutral) {
    if(observed>=0){y[0]=observed?1.3:-15;y[1]=observed?-6.7:1.3;}
    State d=derivative(neutral?t:localTime(t),y,p);
    if(observed>=0){d[0]=0;d[1]=0;}
    return d;
}
static State stepObserved(double t,State y,double h,const Parameters& p,int observed,bool neutral=false) {
    State a=rhsObserved(t,y,p,observed,neutral),v;
    for(int k=0;k<6;k++)v[k]=y[k]+h*a[k]/2;
    State b=rhsObserved(t+h/2,v,p,observed,neutral);
    for(int k=0;k<6;k++)v[k]=y[k]+h*b[k]/2;
    State c=rhsObserved(t+h/2,v,p,observed,neutral);
    for(int k=0;k<6;k++)v[k]=y[k]+h*c[k];
    State d=rhsObserved(t+h,v,p,observed,neutral);
    for(int k=0;k<6;k++)y[k]+=h*(a[k]+2*b[k]+2*c[k]+d[k])/6;
    for(double value:y)if(!std::isfinite(value))throw std::runtime_error("Nonfinite state");
    return y;
}
static State forceObserved(State y,double start,double end,const Parameters& p,int awake,double seconds) {
    for(double cursor=start;cursor<end-1e-10;) {
        double h=std::min(seconds/3600,end-cursor);
        y=stepObserved(cursor,y,h,p,awake);cursor+=h;
    }
    return y;
}
static std::vector<State> neutralTrace(const Parameters& p,int days,double seconds) {
    State y={.6,-6.7,14.6,.35,-.86,-.59};
    const int steps=static_cast<int>(std::llround(days*86400/seconds));
    if(days<1 || std::abs(steps*seconds-days*86400)>1e-6)throw std::runtime_error("Invalid warmup");
    // The fixed schedule is explicit assumed input, not infant history or an
    // inferred future sleep pattern. Split at minute and schedule boundaries.
    auto minute=[&](double t) {
        int hour=static_cast<int>(std::floor(t+1e-8))%24;
        int awake=hour>=7 && hour<19;
        const int sub=static_cast<int>(std::llround(60/seconds));
        if(sub<1 || std::abs(sub*seconds-60)>1e-8)throw std::runtime_error("Forcing step must divide minute");
        for(int j=0;j<sub;j++)y=stepObserved(t+j*seconds/3600,y,seconds/3600,p,awake,true);
    };
    for(int m=0;m<days*1440;m++)minute(m/60.);
    std::vector<State> trace;trace.push_back(y);
    for(int m=0;m<1440;m++){minute(days*24+m/60.);trace.push_back(y);}
    return trace;
}
int main(int argc,char** argv) {
    try {
        if(argc!=5)throw std::runtime_error("Use input.tsv forecastSeconds forcingSeconds neutralDays");
        const double forecastStep=std::stod(argv[2])/3600,forcing=std::stod(argv[3]);
        const int days=std::stoi(argv[4]);
        if(!(forecastStep>0 && forecastStep<=1./3600 && forcing>0 && forcing<=60))throw std::runtime_error("Invalid steps");
        std::ifstream in(argv[1]);int nq,np,no;in>>nq>>np>>no;
        if(!in || nq<1 || np<1 || no<1)throw std::runtime_error("Invalid header");
        std::vector<Parameters> parameters(np);
        for(auto& p:parameters){in>>p.chi>>p.mu>>p.circadian>>p.bias;if(!(p.chi>0&&p.mu>0))throw std::runtime_error("Invalid parameters");}
        for(int i=0;i<no;i++){LocalOffset o;in>>o.t>>o.hours;localOffsets.push_back(o);}
        std::vector<std::vector<State>> traces;
        for(const auto& p:parameters)traces.push_back(neutralTrace(p,days,forcing));
        std::cout<<std::setprecision(17)<<"[";
        for(int i=0;i<nq;i++) {
            double now,start;int ni;in>>now>>start>>ni;
            if(!in || ni<0 || start>now)throw std::runtime_error("Invalid query");
            std::vector<std::pair<double,double>> intervals(ni);double cursor=start;
            for(auto& s:intervals){in>>s.first>>s.second;if(s.first<cursor-1e-9 || s.second<s.first || s.second>now+1e-9)throw std::runtime_error("Noncausal interval");cursor=s.second;}
            if(!in)throw std::runtime_error("Truncated input");
            const double clock=localTime(start)-24*std::floor(localTime(start)/24);
            const double phase=clock*60;const int minute=std::min(1439,static_cast<int>(std::floor(phase)));
            const double fraction=phase-minute;
            if(i)std::cout<<",";std::cout<<"[";
            for(int j=0;j<np;j++) {
                State y=traces[j][minute];
                for(int k=2;k<6;k++)y[k]+=(traces[j][minute+1][k]-y[k])*fraction;
                cursor=start;const auto& p=parameters[j];
                for(const auto& s:intervals){y=forceObserved(y,cursor,s.first,p,1,forcing);y=forceObserved(y,s.first,s.second,p,0,forcing);cursor=s.second;}
                y=forceObserved(y,cursor,now,p,1,forcing);y[0]=1.3;y[1]=-6.7;
                State initial=y;double prediction=480;
                for(double t=0;t<8-1e-10;t+=forecastStep) {
                    const double h=std::min(forecastStep,8-t);State next=stepObserved(now+t,y,h,p,-1);
                    const double before=y[0]-y[1],after=next[0]-next[1];
                    if(before>0 && after<=0){prediction=std::clamp((t+h*before/(before-after))*60,1.,480.);break;}
                    y=next;
                }
                if(j)std::cout<<",";std::cout<<"["<<prediction;
                for(int k=2;k<6;k++)std::cout<<","<<initial[k];std::cout<<"]";
            }
            std::cout<<"]";
            if((i+1)%200==0)std::cerr<<"Completed queries: "<<i+1<<"\n";
        }
        std::cout<<"]\n";
    }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}
}
