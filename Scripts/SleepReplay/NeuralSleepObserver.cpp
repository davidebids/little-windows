// Research observer: completed diary intervals force the slow model states.
// This observation rule is a new assumption, not the upstream fitting method.
#define main neutral_model_main
#include "NeuralSleepCore.cpp"
#undef main
#include <algorithm>
struct Offset { double t, hours; };
static std::vector<Offset> offsets;
static double clock_at(double t) {
    auto it=std::upper_bound(offsets.begin(),offsets.end(),t,
        [](double v,const Offset& o){return v<o.t;});
    if(it==offsets.begin())throw std::runtime_error("Missing time zone offset");
    return t+(--it)->hours;
}
static State rhs(double t, State y, const Parameters& p, int observed) {
    if(observed>=0){y[0]=observed?1.3:-15;y[1]=observed?-6.7:1.3;}
    State d=derivative(clock_at(t),y,p);
    if(observed>=0){d[0]=0;d[1]=0;}
    return d;
}
static State step(double t, State y,double h,const Parameters& p,int observed) {
    State a=rhs(t,y,p,observed),v;
    for(int k=0;k<6;k++)v[k]=y[k]+h*a[k]/2;
    State b=rhs(t+h/2,v,p,observed);
    for(int k=0;k<6;k++)v[k]=y[k]+h*b[k]/2;
    State c=rhs(t+h/2,v,p,observed);
    for(int k=0;k<6;k++)v[k]=y[k]+h*c[k];
    State d=rhs(t+h,v,p,observed);
    for(int k=0;k<6;k++)y[k]+=h/6*(a[k]+2*b[k]+2*c[k]+d[k]);
    for(double v:y)if(!std::isfinite(v))throw std::runtime_error("Nonfinite observer state");
    return y;
}
static State force(State y,double start,double end,const Parameters& p,int awake,double seconds) {
    double cursor=start;
    while(cursor<end-1e-10){double h=std::min(seconds/3600,end-cursor);y=step(cursor,y,h,p,awake);cursor+=h;}
    return y;
}
int main(int argc,char** argv) {
    try {
        if(argc!=4)throw std::runtime_error("Use observer input.tsv forecastSeconds forcingSeconds");
        double forecastStep=std::stod(argv[2])/3600,forceSeconds=std::stod(argv[3]);
        if(!(forecastStep>0 && forecastStep<=1.0/3600 && forceSeconds>0 && forceSeconds<=60))throw std::runtime_error("Invalid steps");
        std::ifstream in(argv[1]);int nq,np,no;in>>nq>>np>>no;
        if(!in || nq<1 || np<1 || no<1)throw std::runtime_error("Invalid header");
        std::vector<Parameters> parameters(np);
        for(auto& p:parameters){in>>p.chi>>p.mu>>p.circadian>>p.bias;if(!(p.chi>0&&p.mu>0))throw std::runtime_error("Invalid parameters");}
        for(int i=0;i<no;i++){Offset o;in>>o.t>>o.hours;offsets.push_back(o);}
        std::cout<<std::setprecision(17)<<"[";
        for(int i=0;i<nq;i++) {
            double now,start;int ni;in>>now>>start>>ni;
            std::vector<std::pair<double,double>> intervals(ni);
            double cursor=start;
            for(auto& s:intervals){in>>s.first>>s.second;if(s.first<cursor-1e-9 || s.second<s.first || s.second>now+1e-9)throw std::runtime_error("Noncausal or overlapping interval");cursor=s.second;}
            if(!in || start>now)throw std::runtime_error("Invalid query");
            if(i)std::cout<<",";std::cout<<"[";
            for(int j=0;j<np;j++) {
                const auto& p=parameters[j];State y={.6,-6.7,14.6,.35,-.86,-.59};cursor=start;
                for(const auto& s:intervals){y=force(y,cursor,s.first,p,1,forceSeconds);y=force(y,s.first,s.second,p,0,forceSeconds);cursor=s.second;}
                y=force(y,cursor,now,p,1,forceSeconds);y[0]=1.3;y[1]=-6.7;
                State initial=y;double prediction=480;
                for(double t=0;t<8-1e-10;t+=forecastStep) {
                    double h=std::min(forecastStep,8-t);State next=step(now+t,y,h,p,-1);
                    double before=y[0]-y[1],after=next[0]-next[1];
                    if(before>0 && after<=0){prediction=std::clamp((t+h*before/(before-after))*60,1.,480.);break;}
                    y=next;
                }
                if(j)std::cout<<",";std::cout<<"["<<prediction;
                for(int k=2;k<6;k++)std::cout<<","<<initial[k];std::cout<<"]";
            }
            std::cout<<"]";
        }
        std::cout<<"]\n";
    }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}
}
