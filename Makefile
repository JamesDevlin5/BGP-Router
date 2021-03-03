default:

run:
	python3 ./router 4 1.2.3.4-peer 5.6.7.8-cust 45.65.76.67-prov 255.255.255.255-cust

get_sim:
	curl -L -o bgp-sim.tar.gz http://course.khoury.neu.edu/cs3700sp21/archive/bgp-sim.tar.gz
	tar xzf bgp-sim.tar.gz

run_sim: get_sim
	./sim milestone

clean_sim:
	- $(RM) bgp-sim.tar.gz
	- $(RM) sim*
	- $(RM) -r tests
