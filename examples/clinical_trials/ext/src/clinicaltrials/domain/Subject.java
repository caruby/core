package clinicaltrials.domain;

public class Subject extends DomainObject
{
    /**
     * The Subject SSN.
     */
    private Integer ssn;

    /**
     * The Subject name.
     */
    private String name;

    /**
     * The Subject address.
     * <p>
     * This property exercises a dependent single-valued, unidirectional reference.
     * </p>
     */
    private Address address;

    public Subject()
    {
    }

    /**
     * @return the Subject SSN
     */
    public Integer getSSN()
    {
        return ssn;
    }

    /**
     * @param name the SSN to set
     */
    public void setSSN(Integer ssn)
    {
        this.ssn = ssn;
    }
    /**
     * @return the Subject name
     */
    public String getName()
    {
        return name;
    }

    /**
     * @param name the name to set
     */
    public void setName(String name)
    {
        this.name = name;
    }

    /**
     * @return the Subject address
     */
    public Address getAddress()
    {
        return address;
    }

    /**
     * @param address the address to set
     */
    public void setAddress(Address address)
    {
        this.address = address;
    }
}
